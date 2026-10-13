import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DeckRepository decks;
  late NoteRepository notes;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    decks = DeckRepository(db);
    notes = NoteRepository(db);
  });
  tearDown(() => db.close());

  test(
    'nested deck rename and moves reject cycles without partial changes',
    () async {
      final root = await decks.createDeck('化学');
      final child = await decks.createDeck('无机', parentId: root);
      await decks.renameDeck(child, '无机化学');
      await expectLater(decks.moveDeck(root, child), throwsArgumentError);
      final rows = await db.select(db.decks).get();
      expect(rows.firstWhere((d) => d.id == root).parentId, isNull);
      expect(rows.firstWhere((d) => d.id == child).name, '无机化学');
      await decks.moveDeck(child, null);
      expect(
        (await db.select(db.decks).get()).every((d) => d.parentId == null),
        isTrue,
      );
    },
  );

  test('basic note has one new card and deduplicated tags', () async {
    final id = await notes.createBasicNote(
      deckId: await decks.createDeck('化学'),
      front: 'CuSO₄',
      back: '硫酸铜',
      tags: ['盐', '盐', ' 蓝色 ', ''],
    );
    expect((await db.select(db.cards).get()).single.state, 0);
    expect((await notes.getNote(id)).tags, ['盐', '蓝色']);
    await notes.deleteNote(id);
    expect(await db.select(db.cards).get(), isEmpty);
    expect(await db.select(db.noteTags).get(), isEmpty);
  });

  test(
    'cloze editing preserves surviving schedule and confirms removed cards',
    () async {
      final id = await notes.createClozeNote(
        deckId: await decks.createDeck('化学'),
        text: '{{c1::蓝色}} {{c2::水}} {{c1::硫酸铜}}',
      );
      final original = await notes.getNote(id);
      final cards = await db.select(db.cards).get();
      expect(cards.map((c) => c.clozeIndex), [1, 2]);
      final survivor = cards.first;
      await (db.update(db.cards)..where((c) => c.id.equals(survivor.id))).write(
        const CardsCompanion(
          state: Value(2),
          dueAtUtc: Value(2000000000123),
          stability: Value(15.5),
          difficulty: Value(4.2),
          lapses: Value(2),
        ),
      );
      final edit = Note(
        id: id,
        deckId: original.deckId,
        type: NoteType.cloze,
        fields: {'text': '{{c1::青蓝色}} {{c3::结晶水}}'},
        tags: ['修订'],
        createdAtUtc: original.createdAtUtc,
        modifiedAtUtc: DateTime.now(),
      );
      await expectLater(
        notes.updateNote(edit),
        throwsA(isA<ClozeRemovalConfirmation>()),
      );
      expect((await notes.getNote(id)).fields, original.fields);
      await notes.updateNote(edit, allowCardRemoval: true);
      final updated = await db.select(db.cards).get();
      expect(updated.map((c) => c.clozeIndex).toSet(), {1, 3});
      final retained = updated.firstWhere((c) => c.clozeIndex == 1);
      expect(retained.id, survivor.id);
      expect(retained.dueAtUtc, 2000000000123);
      expect(retained.stability, 15.5);
      expect(retained.lapses, 2);
      expect(updated.firstWhere((c) => c.clozeIndex == 3).state, 0);
      expect((await notes.getNote(id)).tags, ['修订']);
    },
  );

  test(
    'invalid content and deleting a deck cannot leave orphan data',
    () async {
      final parent = await decks.createDeck('化学');
      final child = await decks.createDeck('填空', parentId: parent);
      await expectLater(
        notes.createBasicNote(deckId: child, front: ' '),
        throwsArgumentError,
      );
      expect(await db.select(db.notes).get(), isEmpty);
      await notes.createClozeNote(deckId: child, text: '{{c1::蓝色}}');
      await decks.deleteDeck(parent);
      expect(await db.select(db.decks).get(), isEmpty);
      expect(await db.select(db.notes).get(), isEmpty);
      expect(await db.select(db.cards).get(), isEmpty);
    },
  );
}
