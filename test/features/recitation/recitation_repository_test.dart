import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/recitation/data/recitation_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late RecitationRepository repository;
  late NoteRepository notes;
  late int deck;
  late int basic;
  late int cloze;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final decks = DeckRepository(db);
    deck = await decks.createDeck('章节');
    final child = await decks.createDeck('第一章', parentId: deck);
    notes = NoteRepository(db);
    basic = await notes.createBasicNote(deckId: deck, front: '基础');
    cloze = await notes.createClozeNote(
      deckId: child,
      text: '{{c1::一}}与{{c2::二}}',
    );
    repository = RecitationRepository(db);
  });
  tearDown(() => db.close());

  test(
    'chapter scope deduplicates cloze notes and survives deletion',
    () async {
      final before = await db.select(db.cards).get();
      final round = await repository.open(deck);
      expect(round.noteIds, [basic, cloze]);
      await repository.savePosition(deck, round, 1);
      expect((await RecitationRepository(db).open(deck)).index, 1);
      expect((await repository.open(deck, includeChildren: false)).noteIds, [
        basic,
      ]);
      expect(await db.select(db.cards).get(), before);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      await notes.deleteNote(cloze);
      final surviving = await repository.open(deck);
      expect(surviving.noteIds, [basic]);
      expect(surviving.index, 0);
    },
  );

  test('random order and current note persist across reopen', () async {
    for (var i = 0; i < 5; i++) {
      await notes.createBasicNote(deckId: deck, front: '额外 $i');
    }
    final round = await repository.open(deck, random: true);
    expect(round.noteIds.toSet().length, 7);
    await repository.savePosition(deck, round, 3);
    final resumed = await RecitationRepository(db).open(deck);
    expect(resumed.random, isTrue);
    expect(resumed.noteIds, round.noteIds);
    expect(resumed.index, 3);
    final added = await notes.createBasicNote(deckId: deck, front: '新笔记');
    final extended = await repository.open(deck);
    expect(extended.noteIds.take(7), round.noteIds);
    expect(extended.noteIds.last, added);
  });
}
