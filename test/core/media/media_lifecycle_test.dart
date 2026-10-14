import 'dart:io';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/media/media_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory directory;
  late MediaRepository media;
  late NoteRepository notes;
  late DeckRepository decks;
  final hash = 'a' * 64;
  final otherHash = 'b' * 64;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final parent = Directory(
      p.join(Directory.current.path, 'build', 'test_media'),
    );
    await parent.create(recursive: true);
    directory = await parent.createTemp('lifecycle_');
    media = MediaRepository(db, directory: directory);
    notes = NoteRepository(db, mediaRepository: media);
    decks = DeckRepository(db, mediaRepository: media);
    for (final key in [hash, otherHash]) {
      await db
          .into(db.media)
          .insert(
            MediaCompanion.insert(
              contentHash: key,
              originalName: 'image.png',
              relativePath: key,
              mimeType: 'image/png',
              byteLength: 1,
              createdAtUtc: 0,
            ),
          );
      await File(p.join(directory.path, key)).writeAsBytes([1]);
    }
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  test(
    'shared media counts once per note and survives deleting one note',
    () async {
      final deck = await decks.createDeck('chemistry');
      final first = await notes.createBasicNote(
        deckId: deck,
        front: '<img src="media:$hash"><img src="media:$hash">',
        back: '[sound:media:$hash]',
      );
      final second = await notes.createBasicNote(
        deckId: deck,
        front: '<img src="media:$hash">',
      );
      expect(
        (await db.select(db.media).get())
            .firstWhere((m) => m.contentHash == hash)
            .referenceCount,
        2,
      );
      await notes.deleteNote(first);
      await media.collectUnused();
      expect(await File(p.join(directory.path, hash)).exists(), isTrue);
      await notes.deleteNote(second);
      await media.collectUnused();
      expect(await File(p.join(directory.path, hash)).exists(), isFalse);
      expect(await db.select(db.media).get(), isEmpty);
    },
  );

  test(
    'editing media references updates counts in the same note transaction',
    () async {
      final deck = await decks.createDeck('chemistry');
      final id = await notes.createBasicNote(
        deckId: deck,
        front: '<img src="media:$hash">',
      );
      final original = await notes.getNote(id);
      final edit = Note(
        id: id,
        deckId: deck,
        type: NoteType.basic,
        fields: {'front': '<img src="media:$otherHash">', 'back': ''},
        tags: [],
        createdAtUtc: original.createdAtUtc,
        modifiedAtUtc: DateTime.now(),
      );
      await notes.updateNote(edit);
      final assets = await db.select(db.media).get();
      expect(assets.firstWhere((m) => m.contentHash == hash).referenceCount, 0);
      expect(
        assets.firstWhere((m) => m.contentHash == otherHash).referenceCount,
        1,
      );
      await db.customStatement(
        "CREATE TRIGGER fail_note BEFORE UPDATE ON notes BEGIN SELECT RAISE(FAIL, 'failure'); END",
      );
      await expectLater(notes.updateNote(original), throwsA(anything));
      expect(
        (await db.select(db.media).get())
            .firstWhere((m) => m.contentHash == otherHash)
            .referenceCount,
        1,
      );
    },
  );

  test(
    'deleting a parent deck releases only media used by its descendant notes',
    () async {
      final root = await decks.createDeck('chemistry');
      final child = await decks.createDeck('inorganic', parentId: root);
      final separate = await decks.createDeck('other');
      await notes.createBasicNote(
        deckId: child,
        front: '<img src="media:$hash">',
      );
      await notes.createBasicNote(
        deckId: separate,
        front: '<img src="media:$hash">',
      );
      await decks.deleteDeck(root);
      expect(
        (await db.select(db.media).get())
            .firstWhere((m) => m.contentHash == hash)
            .referenceCount,
        1,
      );
      await media.collectUnused();
      expect(await File(p.join(directory.path, hash)).exists(), isTrue);
    },
  );

  test('cleanup rechecks notes and refuses unsafe stored paths', () async {
    final deck = await decks.createDeck('chemistry');
    await notes.createBasicNote(deckId: deck, front: '<img src="media:$hash">');
    await db.customStatement('UPDATE media SET reference_count = 0');
    await db.customStatement(
      'UPDATE media SET relative_path = ? WHERE content_hash = ?',
      ['../outside', otherHash],
    );
    await media.collectUnused();
    expect(await File(p.join(directory.path, hash)).exists(), isTrue);
    expect((await db.select(db.media).get()).length, 2);
  });
}
