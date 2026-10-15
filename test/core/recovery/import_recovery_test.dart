import 'dart:convert';
import 'dart:io';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/database/database_connection.dart';
import 'package:cuso4_flashcards/core/recovery/import_recovery.dart';
import 'package:cuso4_flashcards/features/import/data/import_recovery_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sql;

void main() {
  late Directory root;
  late File databaseFile;
  final orphan = 'a' * 64;
  final shared = 'b' * 64;
  final referenced = 'c' * 64;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('import_recovery_');
    databaseFile = File(p.join(root.path, 'cuso4.sqlite'));
    final db = AppDatabase(NativeDatabase(databaseFile));
    await db.customSelect('SELECT 1').get();
    await db.customStatement(
      "INSERT INTO decks (id,name,created_at_utc,modified_at_utc) VALUES (1,'已学牌组',1,1)",
    );
    await db.customStatement(
      'INSERT INTO notes (id,deck_id,note_type,fields_json,created_at_utc,modified_at_utc) VALUES (1,1,0,?,1,1)',
      [
        jsonEncode({'Front': '<img src="media:$referenced">', 'Back': '答案'}),
      ],
    );
    await db.customStatement(
      'INSERT INTO cards (id,note_id,due_at_utc,state,stability,difficulty,repetitions,lapses,last_review_at_utc) VALUES (1,1,123456,2,8.5,4.2,9,1,123)',
    );
    await db.customStatement(
      "INSERT INTO media (content_hash,original_name,relative_path,mime_type,byte_length,reference_count,created_at_utc) VALUES (?,'shared.png',?,'image/png',1,0,1)",
      [shared, shared],
    );
    await db.close();
  });
  tearDown(() async => root.delete(recursive: true));

  void job(sql.Database db, String status) => db.execute(
    'INSERT INTO import_jobs (source_name,status,created_at_utc,modified_at_utc) VALUES (?,?,1,1)',
    ['test.apkg', status],
  );

  Directory stage(String name, {Object? journal}) {
    final dir = Directory(p.join(root.path, 'media', '.imports', name))
      ..createSync(recursive: true);
    File(p.join(dir.path, 'partial')).writeAsStringSync('partial');
    if (journal != null) {
      File(p.join(dir.path, 'journal.json'))
          .writeAsStringSync(jsonEncode(journal));
    }
    return dir;
  }

  File media(String hash) {
    final file = File(p.join(root.path, 'media', hash));
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync('x');
  }

  void recover() {
    final raw = sql.sqlite3.open(databaseFile.path);
    try {
      ImportRecovery(root).run(raw);
    } finally {
      raw.close();
    }
  }

  test('production startup rolls back interrupted import and protects saved learning and media', () async {
    final raw = sql.sqlite3.open(databaseFile.path);
    job(raw, 'running');
    final staging = stage(
      'job_ABC123',
      journal: {
        'version': 1,
        'newFiles': [orphan, shared, referenced],
      },
    );
    final orphanFile = media(orphan);
    final sharedFile = media(shared);
    final referencedFile = media(referenced);
    raw.execute('BEGIN IMMEDIATE');
    raw.execute(
      "INSERT INTO decks (name,created_at_utc,modified_at_utc) VALUES ('未提交',1,1)",
    );
    raw.close(); // Process loss closes the connection without committing.

    final db = AppDatabase(openLocalDatabase(root: root));
    expect((await db.select(db.importJobs).get()).single.status, 'interrupted');
    expect((await db.select(db.decks).get()).single.name, '已学牌组');
    final card = (await db.select(db.cards).get()).single;
    expect(
      [
        card.state,
        card.stability,
        card.difficulty,
        card.repetitions,
        card.lapses,
        card.dueAtUtc,
        card.lastReviewAtUtc,
      ],
      [2, 8.5, 4.2, 9, 1, 123456, 123],
    );
    expect(orphanFile.existsSync(), isFalse);
    expect(sharedFile.existsSync(), isTrue);
    expect(referencedFile.existsSync(), isTrue);
    expect(staging.existsSync(), isFalse);
    final repository = ImportRecoveryRepository(db);
    final notice = (await repository.watch().first)!;
    expect(notice.interruptedJobs, 1);
    expect(notice.cleanupFailures, 0);
    await db.close();

    recover();
    final reopened = AppDatabase(openLocalDatabase(root: root));
    final notices = ImportRecoveryRepository(reopened);
    final same = (await notices.watch().first)!;
    expect(same.raw, notice.raw);
    await notices.acknowledge(same);
    expect(await notices.watch().first, isNull);
    await reopened.close();
    recover();
    final finalDb = AppDatabase(openLocalDatabase(root: root));
    expect(await ImportRecoveryRepository(finalDb).watch().first, isNull);
    await finalDb.close();
  });

  test('completed imports keep media and do not ask for retry', () async {
    final raw = sql.sqlite3.open(databaseFile.path);
    job(raw, 'completed');
    raw.close();
    final staging = stage(
      'job_DONE',
      journal: {
        'version': 1,
        'newFiles': [shared],
      },
    );
    final saved = media(shared);
    recover();
    expect(saved.existsSync(), isTrue);
    expect(staging.existsSync(), isFalse);
    final db = AppDatabase(NativeDatabase(databaseFile));
    expect((await db.select(db.importJobs).get()).single.status, 'completed');
    expect(await ImportRecoveryRepository(db).watch().first, isNull);
    await db.close();
  });

  test(
    'legacy staging is cleaned without guessing ownership of media files',
    () {
      final old = stage('job_OLD');
      final extraction = stage('cuso4_apkg_ABC');
      final unknown = stage('my_files');
      final loose = media(orphan);
      recover();
      expect(old.existsSync(), isFalse);
      expect(extraction.existsSync(), isFalse);
      expect(unknown.existsSync(), isTrue);
      expect(loose.existsSync(), isTrue);
    },
  );

  test('invalid journal retains uncertain files and warns without blocking learning', () async {
    final staging = stage(
      'job_BAD',
      journal: {
        'version': 1,
        'newFiles': [orphan, '../outside'],
      },
    );
    final loose = media(orphan);
    recover();
    expect(staging.existsSync(), isTrue);
    expect(loose.existsSync(), isTrue);
    final db = AppDatabase(NativeDatabase(databaseFile));
    final repo = ImportRecoveryRepository(db);
    final old = (await repo.watch().first)!;
    expect(old.interruptedJobs, 0);
    expect(old.cleanupFailures, 1);
    await db.close();
    recover();
    final reopened = AppDatabase(NativeDatabase(databaseFile));
    final newerRepo = ImportRecoveryRepository(reopened);
    final newer = (await newerRepo.watch().first)!;
    expect(newer.cleanupFailures, 1);
    expect(newer.generation, greaterThan(old.generation));
    await newerRepo.acknowledge(old);
    expect((await newerRepo.watch().first)!.raw, newer.raw);
    expect((await reopened.select(reopened.cards).get()).length, 1);
    await reopened.close();

    // A later successful cleanup clears an obsolete cleanup-only warning.
    File(p.join(staging.path, 'journal.json')).writeAsStringSync(
      jsonEncode({
        'version': 1,
        'newFiles': [orphan],
      }),
    );
    recover();
    final cleaned = AppDatabase(NativeDatabase(databaseFile));
    expect(await ImportRecoveryRepository(cleaned).watch().first, isNull);
    expect(staging.existsSync(), isFalse);
    expect(loose.existsSync(), isFalse);
    await cleaned.close();
  });

  test('malformed saved note retains journal candidates conservatively', () {
    final raw = sql.sqlite3.open(databaseFile.path);
    raw.execute("UPDATE notes SET fields_json = 'invalid'");
    raw.close();
    final staging = stage(
      'job_BADNOTE',
      journal: {
        'version': 1,
        'newFiles': [orphan],
      },
    );
    final loose = media(orphan);
    recover();
    expect(loose.existsSync(), isTrue);
    expect(staging.existsSync(), isTrue);
  });
}
