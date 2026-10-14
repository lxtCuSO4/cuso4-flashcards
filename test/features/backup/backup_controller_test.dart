import 'dart:io';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/features/backup/application/backup_controller.dart';
import 'package:cuso4_flashcards/features/backup/data/backup_platform.dart';
import 'package:cuso4_flashcards/features/backup/data/backup_service.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

class LocalFiles extends BackupPlatform {
  File? selected;
  bool saveResult = true;
  int exports = 0;
  @override
  Future<int?> availableBytes() async => 1024 * 1024 * 1024;
  @override
  Future<File?> pickRestoreFile() async => selected;
  @override
  Future<bool> saveBackup(File file) async {
    expect(await file.exists(), isTrue);
    exports++;
    return saveResult;
  }
}

void main() {
  late Directory root;
  late AppDatabase db;
  late LocalFiles files;
  late BackupController controller;
  late bool importBusy;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cuso4_backup_controller_');
    db = AppDatabase(NativeDatabase(File(p.join(root.path, 'cuso4.sqlite'))));
    await DeckRepository(db).createDeck('原牌组');
    files = LocalFiles();
    importBusy = false;
    controller = BackupController(
      database: () => db,
      root: () async => root,
      platform: files,
      importBusy: () => importBusy,
      databaseChanged: () {
        db = AppDatabase(
          NativeDatabase(File(p.join(root.path, 'cuso4.sqlite'))),
        );
      },
    );
  });
  tearDown(() async {
    controller.dispose();
    await db.close();
    await root.delete(recursive: true);
  });

  test(
    'successful export records time; picker cancellation records no success',
    () async {
      files.saveResult = false;
      await controller.export();
      expect(await db.select(db.appSettings).get(), isEmpty);
      expect(controller.busy, isFalse);
      files.saveResult = true;
      await controller.export();
      final settings = {
        for (final s in await db.select(db.appSettings).get())
          s.key: s.valueJson,
      };
      expect(DateTime.tryParse(settings['lastBackupUtc']!), isNotNull);
      expect(int.parse(settings['lastBackupBytes']!), greaterThan(0));
      expect(files.exports, 2);
      expect(
        await Directory(p.join(root.path, 'backup-work')).list().toList(),
        isEmpty,
      );
    },
  );

  test('import in progress refuses backup and restore', () async {
    importBusy = true;
    await controller.export();
    expect(controller.error, contains('导入'));
    await controller.restore(confirm: () async => true);
    expect(controller.error, contains('导入'));
    expect(files.exports, 0);
    expect((await db.select(db.decks).get()).single.name, '原牌组');
  });

  test('declining confirmation preserves data and clears staging', () async {
    files.selected = await BackupService(db, root).create();
    var asked = false;
    await controller.restore(
      confirm: () async {
        asked = true;
        return false;
      },
    );
    expect(asked, isTrue);
    expect(controller.restored, isFalse);
    expect((await db.select(db.decks).get()).single.name, '原牌组');
    expect(
      await Directory(p.join(root.path, '.cuso4-recovery')).exists(),
      isFalse,
    );
    await BackupService.discard(files.selected!);
    expect(
      await Directory(p.join(root.path, 'backup-work')).list().toList(),
      isEmpty,
    );
  });

  test(
    'restore reopens database, exports the automatic safety snapshot',
    () async {
      files.selected = await BackupService(db, root).create();
      await DeckRepository(db).createDeck('恢复前新增');
      await controller.restore(confirm: () async => true);
      expect(controller.restored, isTrue);
      expect(await db.select(db.decks).get(), hasLength(1));
      expect(controller.hasRecovery, isTrue);
      await controller.export(previous: true);
      expect(files.exports, 1);
      await BackupService.discard(files.selected!);
    },
  );

  test('restore invalidates live Riverpod streams and reopens without stale database access', () async {
    await db.close();
    final live = await Directory(p.join(root.path, 'provider-test')).create();
    final container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWith((ref) {
          final current = AppDatabase(
            NativeDatabase(File(p.join(live.path, 'cuso4.sqlite'))),
          );
          ref.onDispose(current.close);
          return current;
        }),
      ],
    );
    final listener = container.listen(settingsProvider, (_, _) {});
    final run = BackupController(
      database: () => container.read(databaseProvider),
      root: () async => live,
      platform: files,
      importBusy: () => false,
      databaseChanged: () => container.invalidate(databaseProvider),
    );
    try {
      await container
          .read(settingsProvider.future)
          .timeout(const Duration(seconds: 3));
      final before = container.read(databaseProvider);
      await DeckRepository(before).createDeck('备份中的牌组');
      files.selected = await BackupService(before, live).create();
      await DeckRepository(before).createDeck('恢复前新增');
      await run.restore(confirm: () async => true);
      expect(run.error, isNull);
      expect(run.restored, isTrue);
      final after = container.read(databaseProvider);
      expect(after, isNot(same(before)));
      expect((await after.select(after.decks).get()).single.name, '备份中的牌组');
      await container.pump();
      await container
          .read(settingsProvider.future)
          .timeout(const Duration(seconds: 3));
    } finally {
      run.dispose();
      listener.close();
      final current = container.read(databaseProvider);
      container.dispose();
      await current.close();
    }
  });
}
