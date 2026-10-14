import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/import/data/apkg_import_service.dart';
import 'package:cuso4_flashcards/features/import/domain/import_error.dart';
import 'package:cuso4_flashcards/features/import/domain/import_progress.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory scratch;
  late Directory mediaDirectory;
  late AppDatabase db;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('apkg_import_test_');
    mediaDirectory = Directory(p.join(scratch.path, 'app_media'));
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    await scratch.delete(recursive: true);
  });

  Future<File> fixture({
    bool includeAudio = true,
    bool unknownBasicModel = false,
    bool withSource = false,
  }) async {
    final collection = File(p.join(scratch.path, 'collection.anki2'));
    final anki = sqlite3.open(collection.path);
    try {
      anki.execute(
        'CREATE TABLE col (decks TEXT NOT NULL, models TEXT NOT NULL)',
      );
      anki.execute(
        'CREATE TABLE notes (id INTEGER, mid INTEGER, flds TEXT, tags TEXT)',
      );
      anki.execute(
        'CREATE TABLE cards (id INTEGER, nid INTEGER, did INTEGER, ord INTEGER)',
      );
      anki.execute('INSERT INTO col VALUES (?, ?)', [
        jsonEncode({
          '1': {'name': 'Chemistry'},
          '2': {'name': 'Chemistry::Inorganic'},
        }),
        jsonEncode({
          '100': {
            'name': 'Basic',
            'type': 0,
            'flds': [
              {'name': 'Front', 'ord': 0},
              {'name': 'Back', 'ord': 1},
              if (withSource) {'name': 'Source', 'ord': 2},
            ],
          },
          '101': {
            'name': 'Cloze',
            'type': 1,
            'flds': [
              {'name': 'Text', 'ord': 0},
              {'name': withSource ? 'Source' : 'Back Extra', 'ord': 1},
            ],
          },
        }),
      ]);
      anki.execute('INSERT INTO notes VALUES (?, ?, ?, ?)', [
        10,
        unknownBasicModel ? 999 : 100,
        '<b>CuSO4</b><img src="salt.png">\u001f硫酸铜'
            '${withSource ? '\u001f教材第一章' : ''}',
        ' chemistry ',
      ]);
      anki.execute('INSERT INTO notes VALUES (?, ?, ?, ?)', [
        11,
        101,
        '{{c1::蓝色}}${withSource ? '与{{c2::晶体}}' : ''}'
            '\u001f${withSource ? '教材第二章' : ''}[sound:clip.mp3]',
        ' cloze ',
      ]);
      anki.execute('INSERT INTO notes VALUES (?, ?, ?, ?)', [
        12,
        100,
        'front\u001fback',
        ' reversed ',
      ]);
      anki.execute('INSERT INTO cards VALUES (?, ?, ?, ?)', [20, 10, 2, 0]);
      anki.execute('INSERT INTO cards VALUES (?, ?, ?, ?)', [21, 11, 2, 0]);
      anki.execute('INSERT INTO cards VALUES (?, ?, ?, ?)', [22, 12, 2, 0]);
      anki.execute('INSERT INTO cards VALUES (?, ?, ?, ?)', [23, 12, 2, 1]);
      if (withSource) {
        anki.execute('INSERT INTO cards VALUES (?, ?, ?, ?)', [24, 11, 2, 1]);
      }
    } finally {
      anki.close();
    }
    final archive = Archive()
      ..addFile(
        ArchiveFile.bytes('collection.anki2', await collection.readAsBytes()),
      )
      ..addFile(
        ArchiveFile.string(
          'media',
          jsonEncode({'0': 'salt.png', '1': 'clip.mp3'}),
        ),
      )
      ..addFile(
        ArchiveFile.bytes('0', [0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10]),
      );
    if (includeAudio) {
      archive.addFile(ArchiveFile.bytes('1', [0x49, 0x44, 0x33, 0, 0, 0]));
    }
    final apkg = File(p.join(scratch.path, 'chemistry.apkg'));
    await apkg.writeAsBytes(ZipEncoder().encodeBytes(archive));
    return apkg;
  }

  test(
    'imports nested decks, supported cards and media as new local data',
    () async {
      final report = await ApkgImportService(
        db,
        mediaDirectory: mediaDirectory,
      ).importFile(await fixture());
      expect(
        (report.decks, report.notes, report.cards, report.media),
        (2, 2, 2, 2),
      );
      expect(report.skippedReasons, {'unsupportedTemplate': 1});
      final decks = await db.select(db.decks).get();
      final root = decks.singleWhere((deck) => deck.name == 'Chemistry');
      expect(root.parentId, isNull);
      final child = decks.singleWhere((deck) => deck.name == 'Inorganic');
      expect(child.parentId, root.id);
      expect(
        (await db.select(db.notes).get()).every(
          (note) => note.deckId == child.id,
        ),
        isTrue,
      );
      final cards = await db.select(db.cards).get();
      expect(
        cards.every(
          (card) =>
              card.state == 0 &&
              card.lastReviewAtUtc == null &&
              card.repetitions == 0,
        ),
        isTrue,
      );
      final media = await db.select(db.media).get();
      expect(media.length, 2);
      expect(media.every((asset) => asset.referenceCount == 1), isTrue);
      final notes = await db.select(db.notes).get();
      final basic = notes.singleWhere((note) => note.noteType == 0);
      final cloze = notes.singleWhere((note) => note.noteType == 1);
      final imageHash = media
          .singleWhere((asset) => asset.originalName == 'salt.png')
          .contentHash;
      final audioHash = media
          .singleWhere((asset) => asset.originalName == 'clip.mp3')
          .contentHash;
      expect(
        (jsonDecode(basic.fieldsJson) as Map)['front'],
        contains('src="media:$imageHash"'),
      );
      expect(
        (jsonDecode(cloze.fieldsJson) as Map)['extra'],
        contains('[sound:media:$audioHash]'),
      );
      for (final asset in media) {
        expect(
          await File(p.join(mediaDirectory.path, asset.relativePath)).exists(),
          isTrue,
        );
      }
    },
  );

  test(
    'imports Basic/Source and Cloze/Source as new cards with provenance',
    () async {
      final report = await ApkgImportService(
        db,
        mediaDirectory: mediaDirectory,
      ).importFile(await fixture(withSource: true));
      expect((report.notes, report.cards, report.media), (2, 3, 2));
      expect(report.skippedReasons, {'unsupportedTemplate': 1});
      final notes = await db.select(db.notes).get();
      final basic = notes.singleWhere((note) => note.noteType == 0);
      final cloze = notes.singleWhere((note) => note.noteType == 1);
      expect(
        (jsonDecode(basic.fieldsJson) as Map)['back'],
        contains('来源：教材第一章'),
      );
      expect(
        (jsonDecode(cloze.fieldsJson) as Map)['extra'],
        contains('来源：教材第二章'),
      );
      expect(
        (jsonDecode(cloze.fieldsJson) as Map)['extra'],
        contains('[sound:media:'),
      );
      final cards = await db.select(db.cards).get();
      expect(
        cards.every(
          (card) =>
              card.state == 0 &&
              card.repetitions == 0 &&
              card.lastReviewAtUtc == null,
        ),
        isTrue,
      );
    },
  );

  test(
    'unknown models are counted as skipped rather than silently lost',
    () async {
      final report = await ApkgImportService(
        db,
        mediaDirectory: mediaDirectory,
      ).importFile(await fixture(unknownBasicModel: true));
      expect(report.notes, 1);
      expect(report.skipped, 2);
      expect(report.skippedReasons, {'unsupportedTemplate': 2});
    },
  );

  test(
    'new compressed collections retain a readable error across the isolate',
    () async {
      final archive = Archive()
        ..addFile(ArchiveFile.string('collection.anki21b', 'unsupported'));
      final file = File(p.join(scratch.path, 'modern.apkg'));
      await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
      await expectLater(
        ApkgImportService(db, mediaDirectory: mediaDirectory).importFile(file),
        throwsA(
          isA<ApkgImportException>().having(
            (e) => e.code,
            'code',
            ImportErrorCode.unsupportedCollectionVersion,
          ),
        ),
      );
      expect((await db.select(db.importJobs).get()).single.status, 'failed');
      expect(await db.select(db.notes).get(), isEmpty);
    },
  );

  test(
    'repeated imports create uniquely named copies of the root deck',
    () async {
      final apkg = await fixture();
      final service = ApkgImportService(db, mediaDirectory: mediaDirectory);
      await service.importFile(apkg);
      await service.importFile(apkg);
      await service.importFile(apkg);
      final decks = await db.select(db.decks).get();
      expect(
        decks
            .where((deck) => deck.parentId == null)
            .map((deck) => deck.name)
            .toSet(),
        {'Chemistry', 'Chemistry (导入)', 'Chemistry (导入 2)'},
      );
      expect(decks.where((deck) => deck.name == 'Inorganic').length, 3);
      expect(
        (await db.select(db.media).get()).every((m) => m.referenceCount == 3),
        isTrue,
      );
    },
  );

  test(
    'merge appends notes under existing decks without replacing them',
    () async {
      final apkg = await fixture();
      final service = ApkgImportService(db, mediaDirectory: mediaDirectory);
      await service.importFile(apkg);
      await service.importFile(apkg, merge: true);
      expect((await db.select(db.decks).get()).length, 2);
      expect((await db.select(db.notes).get()).length, 4);
    },
  );

  test('database failure rolls back cards and newly moved media', () async {
    await db.select(db.decks).get();
    await db.customStatement(
      "CREATE TRIGGER fail_commit BEFORE UPDATE ON import_jobs WHEN NEW.status = 'completed' BEGIN SELECT RAISE(FAIL, 'commit failure'); END",
    );
    final service = ApkgImportService(db, mediaDirectory: mediaDirectory);
    await expectLater(
      service.importFile(await fixture()),
      throwsA(
        isA<ApkgImportException>().having(
          (error) => error.code,
          'code',
          ImportErrorCode.transactionFailed,
        ),
      ),
    );
    expect(await db.select(db.decks).get(), isEmpty);
    expect(await db.select(db.notes).get(), isEmpty);
    expect(await db.select(db.cards).get(), isEmpty);
    if (await mediaDirectory.exists()) {
      expect(
        mediaDirectory.listSync(recursive: true).whereType<File>(),
        isEmpty,
      );
    }
  });

  test('cancellation after a note write rolls back the whole import', () async {
    var cancelled = false;
    final service = ApkgImportService(db, mediaDirectory: mediaDirectory);
    await expectLater(
      service.importFile(
        await fixture(),
        isCancelled: () => cancelled,
        onProgress: (p) {
          if (p.phase == ImportPhase.saving && p.completed == 1) {
            cancelled = true;
          }
        },
      ),
      throwsA(
        isA<ApkgImportException>().having(
          (error) => error.code,
          'code',
          ImportErrorCode.cancelled,
        ),
      ),
    );
    expect(await db.select(db.decks).get(), isEmpty);
    expect(await db.select(db.notes).get(), isEmpty);
    expect(await db.select(db.media).get(), isEmpty);
  });

  test('missing media is reported without discarding its note', () async {
    final service = ApkgImportService(db, mediaDirectory: mediaDirectory);
    final report = await service.importFile(await fixture(includeAudio: false));
    expect(report.notes, 2);
    expect(report.missingMedia, 1);
    expect(report.media, 1);
  });

  test(
    'reports real stages and persists a completed job with skip counts',
    () async {
      final stages = <ImportPhase>[];
      final report = await ApkgImportService(db, mediaDirectory: mediaDirectory)
          .importFile(
            await fixture(),
            onProgress: (progress) => stages.add(progress.phase),
          );
      expect(
        stages.toSet(),
        containsAll([
          ImportPhase.extracting,
          ImportPhase.reading,
          ImportPhase.media,
          ImportPhase.saving,
        ]),
      );
      final job = (await db.select(db.importJobs).get()).single;
      expect(job.status, 'completed');
      expect(jsonDecode(job.reportJson!)['cards'], report.cards);
      expect(
        (await db.select(db.importJobErrors).get()).single.reason,
        'unsupportedTemplate',
      );
    },
  );

  test(
    'cancel during background parsing leaves no data or staging files',
    () async {
      var cancelled = false;
      await expectLater(
        ApkgImportService(db, mediaDirectory: mediaDirectory).importFile(
          await fixture(),
          isCancelled: () => cancelled,
          onProgress: (progress) {
            if (progress.phase == ImportPhase.reading) cancelled = true;
          },
        ),
        throwsA(
          isA<ApkgImportException>().having(
            (e) => e.code,
            'code',
            ImportErrorCode.cancelled,
          ),
        ),
      );
      expect(await db.select(db.notes).get(), isEmpty);
      expect((await db.select(db.importJobs).get()).single.status, 'cancelled');
      expect(
        mediaDirectory.listSync(recursive: true).whereType<File>(),
        isEmpty,
      );
    },
  );
}
