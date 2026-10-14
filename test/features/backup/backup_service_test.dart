import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/backup/data/backup_service.dart';
import 'package:cuso4_flashcards/features/backup/data/restore_service.dart';
import 'package:cuso4_flashcards/features/backup/domain/backup_manifest.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

void main() {
  late Directory root;
  late AppDatabase db;
  late bool closed;
  late String imageHash;
  late int cardId;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cuso4_backup_test_');
    db = AppDatabase(
      NativeDatabase(
        File(p.join(root.path, 'cuso4.sqlite')),
        setup: (db) => db.execute('PRAGMA journal_mode=WAL'),
      ),
    );
    closed = false;
    final deck = await DeckRepository(db).createDeck('第一章');
    final bytes = utf8.encode('local image fixture');
    imageHash = sha256.convert(bytes).toString();
    await Directory(p.join(root.path, 'media')).create();
    await File(p.join(root.path, 'media', imageHash)).writeAsBytes(bytes);
    await db
        .into(db.media)
        .insert(
          MediaCompanion.insert(
            contentHash: imageHash,
            originalName: '图片.png',
            relativePath: imageHash,
            mimeType: 'image/png',
            byteLength: bytes.length,
            createdAtUtc: 1,
          ),
        );
    await NoteRepository(db).createBasicNote(
      deckId: deck,
      front: '问题<img src="media:$imageHash">',
      back: '答案',
      tags: ['操作系统'],
    );
    cardId = (await db.select(db.cards).get()).single.id;
    await StudyRepository(db).setFavorite(cardId, true);
    await db
        .into(db.appSettings)
        .insert(AppSettingsCompanion.insert(key: 'theme', valueJson: 'dark'));
    await (db.update(db.cards)..where((c) => c.id.equals(cardId))).write(
      const CardsCompanion(repetitions: Value(7), stability: Value(12.5)),
    );
    final state = jsonEncode((await db.select(db.cards).get()).single.toJson());
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            cardId: cardId,
            reviewedAtUtc: 1,
            rating: 3,
            elapsedMilliseconds: 5000,
            beforeStateJson: state,
            afterStateJson: state,
          ),
        );
  });
  tearDown(() async {
    if (!closed) await db.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<File> export() => BackupService(db, root).create();
  Future<void> close() async {
    await db.close();
    closed = true;
  }

  test('manifest round-trip keeps strict version, hashes and settings', () {
    final value = BackupManifest(
      createdAtUtc: DateTime.utc(2026, 10, 15),
      database: BackupEntry(hash: 'a' * 64, bytes: 4096),
      media: {imageHash: BackupEntry(hash: imageHash, bytes: 19)},
    );
    final parsed = BackupManifest.fromJson(
      jsonDecode(jsonEncode(value.toJson())),
    );
    expect(parsed.toJson(), value.toJson());
    final newer = value.toJson()..['formatVersion'] = 999;
    expect(
      () => BackupManifest.fromJson(newer),
      throwsA(isA<BackupException>()),
    );
    final missing = value.toJson()..remove('includesSettings');
    expect(
      () => BackupManifest.fromJson(missing),
      throwsA(isA<BackupException>()),
    );
    final unsafe = value.toJson()
      ..['media'] = {
        '../escape': {'sha256': 'a' * 64, 'bytes': 1},
      };
    expect(
      () => BackupManifest.fromJson(unsafe),
      throwsA(isA<BackupException>()),
    );
  });

  test('WAL snapshot includes progress, favorites, settings and referenced media only', () async {
    await File(p.join(root.path, 'media', 'unused')).writeAsString('not used');
    final file = await export();
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    expect(archive.files.map((f) => f.name).toSet(), {
      'manifest.json',
      'database.sqlite',
      'media/$imageHash',
    });
    final prepared = await RestoreService(root).prepare(file);
    final copy = sql.sqlite3.open(
      p.join(prepared.path, 'cuso4.sqlite'),
      mode: sql.OpenMode.readOnly,
    );
    try {
      expect(
        copy.select('SELECT repetitions, stability FROM cards').single.values,
        [7, 12.5],
      );
      expect(
        copy.select('SELECT card_id FROM favorites').single['card_id'],
        cardId,
      );
      expect(
        copy
            .select("SELECT value_json FROM app_settings WHERE key='theme'")
            .single['value_json'],
        'dark',
      );
      expect(copy.select('SELECT name FROM tags').single['name'], '操作系统');
      expect(copy.select('SELECT rating FROM review_logs').single['rating'], 3);
    } finally {
      copy.close();
    }
    expect(
      await File(p.join(prepared.path, 'media', imageHash)).readAsString(),
      'local image fixture',
    );
  });

  test(
    'cancel removes incomplete package without touching live data',
    () async {
      await expectLater(
        BackupService(db, root).create(isCancelled: () => true),
        throwsA(isA<BackupException>()),
      );
      expect(await db.select(db.cards).get(), hasLength(1));
      final jobs = Directory(p.join(root.path, 'backup-work'));
      if (await jobs.exists()) expect(await jobs.list().toList(), isEmpty);
    },
  );

  test('missing referenced media refuses an incomplete backup', () async {
    await File(p.join(root.path, 'media', imageHash)).delete();
    await expectLater(export(), throwsA(isA<BackupException>()));
    expect(await db.select(db.notes).get(), hasLength(1));
  });

  test('low space is rejected before creating or replacing data', () async {
    await expectLater(
      BackupService(db, root, availableBytes: () async => 0).create(),
      throwsA(isA<BackupException>()),
    );
    final file = await export();
    await expectLater(
      RestoreService(root, availableBytes: () async => 0).prepare(file),
      throwsA(isA<BackupException>()),
    );
    expect(await db.select(db.cards).get(), hasLength(1));
  });

  test(
    'tampered checksum and unsafe archive never change the live database',
    () async {
      final file = await export();
      final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
      final changed = Archive();
      for (final entry in archive) {
        changed.addFile(
          ArchiveFile.bytes(
            entry.name,
            entry.name.startsWith('media/')
                ? utf8.encode('tampered')
                : entry.content,
          ),
        );
      }
      final bad = File(p.join(root.path, 'bad.cuso4backup'));
      await bad.writeAsBytes(ZipEncoder().encode(changed));
      await expectLater(
        RestoreService(root).prepare(bad),
        throwsA(isA<BackupException>()),
      );
      await bad.writeAsBytes(
        ZipEncoder().encode(
          Archive()..addFile(ArchiveFile.string('../escape', 'bad')),
        ),
      );
      await expectLater(
        RestoreService(root).prepare(bad),
        throwsA(isA<BackupException>()),
      );
      expect(await db.select(db.cards).get(), hasLength(1));
      expect(await File(p.join(root.path, 'escape')).exists(), isFalse);
    },
  );

  test(
    'restore replaces data and keeps an exportable pre-restore snapshot',
    () async {
      final file = await export();
      await (db.update(db.appSettings)..where((s) => s.key.equals('theme')))
          .write(const AppSettingsCompanion(valueJson: Value('light')));
      final service = RestoreService(root);
      final prepared = await service.prepare(file);
      await close();
      await service.apply(prepared);
      final fresh = AppDatabase(
        NativeDatabase(File(p.join(root.path, 'cuso4.sqlite'))),
      );
      try {
        expect(
          (await fresh.select(fresh.appSettings).get()).single.valueJson,
          'dark',
        );
        expect((await fresh.select(fresh.cards).get()).single.repetitions, 7);
        expect(await fresh.select(fresh.favorites).get(), hasLength(1));
      } finally {
        await fresh.close();
      }
      final previous = sql.sqlite3.open(
        p.join(root.path, '.cuso4-recovery', 'cuso4.sqlite'),
        mode: sql.OpenMode.readOnly,
      );
      try {
        expect(
          previous
              .select('SELECT value_json FROM app_settings')
              .single['value_json'],
          'light',
        );
      } finally {
        previous.close();
      }
      expect(
        await File(p.join(root.path, '.cuso4-recovery', 'media', imageHash))
            .exists(),
        isTrue,
      );
    },
  );

  test('failure during replacement rolls database and media back', () async {
    final prepared = await RestoreService(root).prepare(await export());
    await (db.update(db.appSettings)..where((s) => s.key.equals('theme')))
        .write(const AppSettingsCompanion(valueJson: Value('light')));
    await close();
    await expectLater(
      RestoreService(
        root,
        afterMove: (step) {
          if (step == 2) {
            throw const FileSystemException('simulated interruption');
          }
        },
      ).apply(prepared),
      throwsA(anything),
    );
    final original = sql.sqlite3.open(
      p.join(root.path, 'cuso4.sqlite'),
      mode: sql.OpenMode.readOnly,
    );
    try {
      expect(
        original
            .select('SELECT value_json FROM app_settings')
            .single['value_json'],
        'light',
      );
    } finally {
      original.close();
    }
    expect(await File(p.join(root.path, 'media', imageHash)).exists(), isTrue);
  });

  test(
    'stage media tampering is rejected before replacing existing data',
    () async {
      final prepared = await RestoreService(root).prepare(await export());
      await File(p.join(prepared.path, 'media', imageHash))
          .writeAsString('changed after validation');
      await close();
      await expectLater(
        RestoreService(root).apply(prepared),
        throwsA(isA<BackupException>()),
      );
      expect(
        await Directory(p.join(root.path, '.cuso4-recovery')).exists(),
        isFalse,
      );
      expect(
        await File(p.join(root.path, 'media', imageHash)).readAsString(),
        'local image fixture',
      );
    },
  );

  test(
    'damaged recovery journal fails closed without removing current data',
    () async {
      await close();
      final before = await File(p.join(root.path, 'cuso4.sqlite'))
          .readAsBytes();
      final job = await Directory(p.join(root.path, '.cuso4-restore')).create();
      await File(p.join(job.path, 'journal.json')).writeAsString('{broken');
      expect(
        () => RestoreService.recoverInterrupted(root),
        throwsA(isA<BackupException>()),
      );
      expect(
        await File(p.join(root.path, 'cuso4.sqlite')).readAsBytes(),
        before,
      );
    },
  );

  test('startup removes only abandoned backup jobs, not current data or safety snapshot', () async {
    final work = await Directory(p.join(root.path, 'backup-work')).create();
    await Directory(p.join(work.path, 'export-abandoned')).create();
    await Directory(p.join(work.path, 'restore-abandoned')).create();
    await File(p.join(work.path, 'keep.txt')).writeAsString('unrelated');
    await Directory(p.join(root.path, '.cuso4-recovery')).create();
    RestoreService.cleanAbandonedJobs(root);
    expect(await work.list().map((e) => p.basename(e.path)).toList(), [
      'keep.txt',
    ]);
    expect(
      await Directory(p.join(root.path, '.cuso4-recovery')).exists(),
      isTrue,
    );
    expect(await db.select(db.cards).get(), hasLength(1));
  });

  test('startup recovery rolls back interrupted moves idempotently', () async {
    await close();
    final job = Directory(p.join(root.path, '.cuso4-restore'));
    await Directory(p.join(job.path, 'previous')).create(recursive: true);
    await File(p.join(job.path, 'journal.json')).writeAsString(
      jsonEncode({
        'phase': 'replacing',
        'existed': {
          'cuso4.sqlite': true,
          'cuso4.sqlite-wal': false,
          'cuso4.sqlite-shm': false,
          'media': true,
        },
      }),
      flush: true,
    );
    await File(p.join(root.path, 'cuso4.sqlite'))
        .rename(p.join(job.path, 'previous', 'cuso4.sqlite'));
    await File(p.join(root.path, 'cuso4.sqlite'))
        .writeAsString('interrupted replacement');
    RestoreService.recoverInterrupted(root);
    RestoreService.recoverInterrupted(root);
    final original = sql.sqlite3.open(
      p.join(root.path, 'cuso4.sqlite'),
      mode: sql.OpenMode.readOnly,
    );
    try {
      expect(original.select('SELECT id FROM cards'), hasLength(1));
    } finally {
      original.close();
    }
    expect(await File(p.join(root.path, 'media', imageHash)).exists(), isTrue);
    expect(await job.exists(), isFalse);
  });
}
