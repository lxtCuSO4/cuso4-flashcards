import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/search/data/search_repository.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late SearchRepository search;
  late int deck, child, other;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    notes = NoteRepository(db);
    search = SearchRepository(db, notes);
    final decks = DeckRepository(db);
    deck = await decks.createDeck('化学');
    child = await decks.createDeck('基础', parentId: deck);
    other = await decks.createDeck('其他');
  });
  tearDown(() => db.close());
  SearchQuery query({
    String text = '',
    int? deckId,
    bool children = true,
    int? type,
    String? tag,
    bool favorites = false,
    int offset = 0,
  }) => (
    text: text,
    deckId: deckId,
    includeChildren: children,
    noteType: type,
    tag: tag,
    favoritesOnly: favorites,
    offset: offset,
  );

  test('search combines literal content, type, tags, favorites and recursive scope before pagination', () async {
    final id = await notes.createClozeNote(
      deckId: child,
      text: '{{c1::铜}} {{c2::CuSO4 100%}}',
      tags: ['盐'],
    );
    await notes.createBasicNote(
      deckId: other,
      front: 'CuSO4 100%',
      tags: ['盐'],
    );
    final cards = await db.select(db.cards).get();
    await StudyRepository(db).setFavorite(cards.first.id, true);
    final result = await search
        .watch(
          query(text: '100%', deckId: deck, type: 1, tag: '盐', favorites: true),
        )
        .first;
    expect(result.items.single.id, id);
    expect(result.items.single.cardCount, 2);
    expect(result.items.single.deckPath, '化学 / 基础');
    expect(
      (await search.watch(query(deckId: deck, children: false)).first).items,
      isEmpty,
    );
    expect(
      (await search.watch(query(text: "%' OR 1=1 --")).first).items,
      isEmpty,
    );
    for (var i = 0; i < 32; i++) {
      await notes.createBasicNote(deckId: deck, front: '匹配 $i');
    }
    final first = await search.watch(query(text: '匹配')).first;
    final last = await search.watch(query(text: '匹配', offset: 30)).first;
    expect(first.items.length, 30);
    expect(first.hasNext, true);
    expect(last.items.length, 2);
    expect(
      first.items
          .map((n) => n.id)
          .toSet()
          .intersection(last.items.map((n) => n.id).toSet()),
      isEmpty,
    );
  });
  test('batch move and tags retain schedules; invalid selection and mid-batch failure roll back', () async {
    final a = await notes.createBasicNote(
      deckId: deck,
      front: 'a',
      tags: ['原标签'],
    );
    final b = await notes.createClozeNote(
      deckId: child,
      text: '{{c1::b}} {{c2::c}}',
    );
    // Exercise a learned card: resetting non-default FSRS data must be detected.
    await db.customStatement(
      'UPDATE cards SET state=2, stability=12.5, difficulty=6, repetitions=3, lapses=1, last_review_at_utc=1000, due_at_utc=999999 WHERE note_id=?',
      [a],
    );
    final before = (await db.select(db.cards).get())
        .map((c) => c.toJson())
        .toList();
    await search.applyBatch({a, b}, action: BatchAction.move, deckId: other);
    await search.applyBatch(
      {a, b},
      action: BatchAction.addTags,
      tags: ['新标签', '新标签'],
    );
    await search.applyBatch(
      {a, b},
      action: BatchAction.removeTags,
      tags: ['原标签'],
    );
    expect((await notes.getNote(a)).tags, ['新标签']);
    expect((await notes.getNote(b)).deckId, other);
    expect(
      (await db.select(db.cards).get()).map((c) => c.toJson()).toList(),
      before,
    );
    await expectLater(
      search.applyBatch({a, 99999}, action: BatchAction.delete),
      throwsStateError,
    );
    await db.customStatement(
      "CREATE TRIGGER fail_delete BEFORE DELETE ON notes WHEN old.id=$b BEGIN SELECT RAISE(FAIL, 'failure'); END",
    );
    await expectLater(
      search.applyBatch({a, b}, action: BatchAction.delete),
      throwsA(anything),
    );
    expect((await db.select(db.notes).get()).length, 2);
    expect(
      (await db.select(db.cards).get()).map((c) => c.toJson()).toList(),
      before,
    );
    await db.customStatement('DROP TRIGGER fail_delete');
    await search.applyBatch({a, b}, action: BatchAction.delete);
    expect(await db.select(db.notes).get(), isEmpty);
    expect(await db.select(db.cards).get(), isEmpty);
  });
}
