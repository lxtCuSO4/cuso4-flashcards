import 'dart:io';
import 'dart:typed_data';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/media/media_repository.dart';
import 'package:cuso4_flashcards/core/media/prepared_image.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/image_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppDatabase db;
  late Directory root;
  late MediaRepository media;
  late NoteRepository notes;
  late int deck;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final parent = Directory(
      p.join(Directory.current.path, 'build', 'test_media'),
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('editor_');
    media = MediaRepository(db, directory: root);
    notes = NoteRepository(db, mediaRepository: media);
    deck = await DeckRepository(db).createDeck('化学');
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test('draft validates content and remains memory only until saved', () async {
    final image = await PreparedImage.fromBytes(
      await imageBytes(),
      name: '硫酸铜.png',
    );
    expect(image.mimeType, 'image/png');
    expect(image.token, matches(r'^media:[a-f0-9]{64}$'));
    expect(await db.select(db.media).get(), isEmpty);
    expect(await root.list().toList(), isEmpty);
    await expectLater(
      PreparedImage.fromBytes(Uint8List.fromList([1, 2, 3]), name: 'fake.png'),
      throwsArgumentError,
    );
    await expectLater(
      PreparedImage.fromBytes(
        (await imageBytes()).sublist(0, 16),
        name: 'broken.png',
      ),
      throwsArgumentError,
    );
    await expectLater(
      PreparedImage.fromBytes(
        Uint8List(PreparedImage.maxBytes + 1),
        name: 'big.png',
      ),
      throwsArgumentError,
    );
  });

  test('save deduplicates shared images, filters unused drafts and preserves schedule', () async {
    final image = await PreparedImage.fromBytes(
      await imageBytes(),
      name: 'photo.png',
    );
    await notes.createBasicNote(
      deckId: deck,
      front: '未引用的图片草稿',
      images: [image],
    );
    expect(await db.select(db.media).get(), isEmpty);
    expect(await root.list().toList(), isEmpty);
    final unused = (await db.select(db.notes).get()).single.id;
    await notes.deleteNote(unused);
    final id = await notes.createBasicNote(
      deckId: deck,
      front: '<img src="${image.token}"><img src="${image.token}">',
      images: [image],
    );
    final before = (await db.select(db.cards).get()).single.toJson();
    final original = await notes.getNote(id);
    await notes.updateNote(
      Note(
        id: id,
        deckId: deck,
        type: NoteType.basic,
        fields: {'front': '新版<img src="${image.token}">', 'back': ''},
        tags: [],
        createdAtUtc: original.createdAtUtc,
        modifiedAtUtc: DateTime.now(),
      ),
      images: [image],
    );
    expect((await db.select(db.cards).get()).single.toJson(), before);
    expect((await db.select(db.media).get()).single.referenceCount, 1);
    await notes.createBasicNote(
      deckId: deck,
      front: '<img src="${image.token}">',
      images: [image],
    );
    expect((await db.select(db.media).get()).single.referenceCount, 2);
    expect(
      (await media.resolve(
        image.token,
        kind: MediaKind.image,
      ))!.file.readAsBytesSync(),
      image.bytes,
    );
    await notes.createBasicNote(deckId: deck, front: '未用图片', images: [image]);
    expect((await db.select(db.media).get()).single.referenceCount, 2);
    expect((await root.list().toList()).length, 1);
  });

  test('failed note save rolls back new media and leaves existing shared files intact', () async {
    final image = await PreparedImage.fromBytes(
      await imageBytes(),
      name: 'photo.png',
    );
    await db.customStatement(
      "CREATE TRIGGER fail_note BEFORE INSERT ON notes BEGIN SELECT RAISE(FAIL, 'failure'); END",
    );
    await expectLater(
      notes.createBasicNote(
        deckId: deck,
        front: '<img src="${image.token}">',
        images: [image],
      ),
      throwsA(anything),
    );
    expect(await db.select(db.media).get(), isEmpty);
    expect(await root.list().toList(), isEmpty);
    await db.customStatement('DROP TRIGGER fail_note');
    await notes.createBasicNote(
      deckId: deck,
      front: '<img src="${image.token}">',
      images: [image],
    );
    await db.customStatement(
      "CREATE TRIGGER fail_note BEFORE INSERT ON notes BEGIN SELECT RAISE(FAIL, 'failure'); END",
    );
    await expectLater(
      notes.createBasicNote(
        deckId: deck,
        front: '<img src="${image.token}">',
        images: [image],
      ),
      throwsA(anything),
    );
    expect((await db.select(db.media).get()).single.referenceCount, 1);
    expect(await media.resolve(image.token, kind: MediaKind.image), isNotNull);
  });
}
