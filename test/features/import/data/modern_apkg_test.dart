import 'dart:convert';
import 'dart:io';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/import/data/apkg_archive_reader.dart';
import 'package:cuso4_flashcards/features/import/data/apkg_import_service.dart';
import 'package:cuso4_flashcards/features/import/domain/import_error.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/modern_apkg_fixture.dart';

void main() {
  late Directory root;
  late AppDatabase db;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('modern_apkg_');
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  test('imports modern Zstd DB, protobuf media, basic/cloze and source as fresh cards', () async {
    final report = await ApkgImportService(
      db,
      mediaDirectory: Directory('${root.path}/assets'),
    ).importFile(await modernApkgFixture(root));
    expect(
      (report.decks, report.notes, report.cards, report.media),
      (2, 2, 3, 1),
    );
    final decks = await db.select(db.decks).get();
    expect(
      decks.singleWhere((d) => d.name == '第一章').parentId,
      decks.singleWhere((d) => d.name == '化学').id,
    );
    final notes = await db.select(db.notes).get();
    expect(jsonDecode(notes.first.fieldsJson)['back'], contains('来源：教材一'));
    expect(jsonDecode(notes.last.fieldsJson)['extra'], contains('来源：教材二'));
    expect(
      (await db.select(db.tags).get()).map((t) => t.name),
      containsAll(['chemistry', 'salt', 'cloze']),
    );
    final asset = (await db.select(db.media).get()).single;
    expect(
      await File('${root.path}/assets/${asset.contentHash}').readAsBytes(),
      fixtureImage,
    );
    expect(
      jsonDecode(notes.first.fieldsJson)['front'],
      contains('media:${asset.contentHash}'),
    );
    expect(
      (await db.select(db.cards).get()).every(
        (c) => c.state == 0 && c.lastReviewAtUtc == null && c.repetitions == 0,
      ),
      true,
    );
  });
  for (final failure in ['hash', 'truncated', 'size', 'version']) {
    test(
      'rejects modern $failure failure without importing data or media',
      () async {
        final file = await modernApkgFixture(
          root,
          badHash: failure == 'hash',
          truncated: failure == 'truncated',
          declaredSize: failure == 'size' ? 2 : null,
          version: failure == 'version' ? 4 : 3,
        );
        await expectLater(
          ApkgImportService(
            db,
            mediaDirectory: Directory('${root.path}/assets'),
          ).importFile(file),
          throwsA(isA<ApkgImportException>()),
        );
        expect(await db.select(db.notes).get(), isEmpty);
        expect(await db.select(db.decks).get(), isEmpty);
        expect(await db.select(db.media).get(), isEmpty);
        final assets = Directory('${root.path}/assets');
        if (await assets.exists()) {
          expect(
            await assets.list(recursive: true).where((e) => e is File).length,
            0,
          );
        }
      },
    );
  }
  test(
    'bounds decoded Zstd size independently of compressed ZIP size',
    () async {
      final file = await modernApkgFixture(root);
      expect(await file.length(), lessThan(4000));
      await expectLater(
        ApkgArchiveReader(maxExtractedBytes: 4000)
            .extract(file, destination: root),
        throwsA(isA<ApkgImportException>()),
      );
      expect(
        await root
            .list()
            .where((e) => e is Directory && e.path.contains('cuso4_apkg_'))
            .length,
        0,
      );
    },
  );
  for (final bad in ['traversal', 'protobuf', 'missingMedia']) {
    test(
      'rejects modern $bad in media manifest and cleans extraction staging',
      () async {
        final file = await modernApkgFixture(
          root,
          mediaName: bad == 'traversal' ? '../salt.png' : 'salt.png',
          manifestBytes: bad == 'protobuf' ? [0x0a, 0xff, 0xff, 0x7f] : null,
          missingMedia: bad == 'missingMedia',
        );
        await expectLater(
          ApkgArchiveReader().extract(file, destination: root),
          throwsA(isA<ApkgImportException>()),
        );
        expect(
          await root
              .list()
              .where((e) => e is Directory && e.path.contains('cuso4_apkg_'))
              .length,
          0,
        );
      },
    );
  }
}
