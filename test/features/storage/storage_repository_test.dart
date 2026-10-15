import 'dart:io';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/media/media_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/storage/storage_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root, folder;
  late AppDatabase db;
  late NoteRepository notes;
  late StorageRepository storage;
  late int deck;
  String hash(String c) => c * 64;
  Future<void> asset(
    String c, {
    bool file = true,
    int count = 0,
    String? path,
  }) async {
    if (file) await File('${folder.path}/${hash(c)}').writeAsBytes([1, 2, 3]);
    await db
        .into(db.media)
        .insert(
          MediaCompanion.insert(
            contentHash: hash(c),
            originalName: '$c.png',
            relativePath: path ?? hash(c),
            mimeType: 'image/png',
            byteLength: 3,
            createdAtUtc: 1,
          ),
        );
    await db.customStatement(
      'UPDATE media SET reference_count=? WHERE content_hash=?',
      [count, hash(c)],
    );
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('storage_test_');
    folder = await Directory('${root.path}/media').create();
    db = AppDatabase(NativeDatabase.memory());
    final media = MediaRepository(db, directory: folder);
    notes = NoteRepository(db, mediaRepository: media);
    storage = StorageRepository(db, media, root: root);
    deck = await DeckRepository(db).createDeck('测试');
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });
  test('rechecks real references, preserves shared files despite stale counters and new references after inspection', () async {
    await asset('a');
    await asset('b', count: 99);
    await notes.createBasicNote(
      deckId: deck,
      front: '<img src="media:${hash('a')}">',
    );
    await notes.createBasicNote(
      deckId: deck,
      front: '<img src="media:${hash('a')}">',
    );
    await db.customStatement(
      'UPDATE media SET reference_count=0 WHERE content_hash=?',
      [hash('a')],
    );
    final before = await storage.inspect();
    expect(
      (before.mediaBytes, before.unusedBytes, before.unusedCount),
      (6, 3, 1),
    );
    await notes.createBasicNote(
      deckId: deck,
      front: '<img src="media:${hash('b')}">',
    );
    final result = await storage.clean();
    expect((result.files, result.bytes, result.failed), (0, 0, 0));
    expect(await File('${folder.path}/${hash('a')}').exists(), true);
    expect(await File('${folder.path}/${hash('b')}').exists(), true);
  });
  test('cleans orphan hash files and missing metadata, retains unknown files, folders and anomalous rows', () async {
    await asset('a', count: 55);
    await asset('b', file: false);
    await asset('c', path: '../external');
    await asset('d', file: false);
    await File('${folder.path}/${hash('e')}').writeAsBytes([4, 5]);
    await File('${folder.path}/keep.png').writeAsString('keep');
    await Directory('${folder.path}/${hash('f')}').create();
    await File('${root.path}/backup.cuso4').writeAsString('backup');
    await notes.createBasicNote(
      deckId: deck,
      front: '<img src="media:${hash('d')}">',
    );
    final before = await storage.inspect();
    expect(
      (before.unusedCount, before.unusedBytes, before.missingCount),
      (2, 5, 1),
    );
    final result = await storage.clean();
    expect((result.files, result.bytes, result.failed), (2, 5, 0));
    expect(
      (await db.select(db.media).get()).map((m) => m.contentHash).toSet(),
      {hash('c'), hash('d')},
    );
    expect(await File('${folder.path}/keep.png').readAsString(), 'keep');
    expect(await Directory('${folder.path}/${hash('f')}').exists(), true);
    expect(await File('${root.path}/backup.cuso4').readAsString(), 'backup');
    expect(await File('${folder.path}/${hash('c')}').exists(), true);
    expect((await storage.inspect()).unusedCount, 0);
  });
}
