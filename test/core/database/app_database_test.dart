import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  const now = 1791936000123;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());
  Future<int> deck() => db
      .into(db.decks)
      .insert(
        DecksCompanion.insert(
          name: '化学',
          createdAtUtc: now,
          modifiedAtUtc: now,
        ),
      );
  Future<int> note(int deckId) => db
      .into(db.notes)
      .insert(
        NotesCompanion.insert(
          deckId: deckId,
          noteType: 0,
          fieldsJson: '{}',
          createdAtUtc: now,
          modifiedAtUtc: now,
        ),
      );

  test('deck, note and new card persist with millisecond timestamps', () async {
    await db.transaction(() async {
      final deckId = await deck();
      final noteId = await note(deckId);
      final cardId = await db
          .into(db.cards)
          .insert(CardsCompanion.insert(noteId: noteId, dueAtUtc: now));
      expect([deckId, noteId, cardId], everyElement(greaterThan(0)));
    });
    final card = await db.select(db.cards).getSingle();
    expect(card.dueAtUtc, now);
    expect(card.state, 0);
    expect(card.stability, isNull);
  });
  test('transaction failure leaves no partial data', () async {
    await expectLater(
      db.transaction(() async {
        await deck();
        throw StateError('cancel');
      }),
      throwsStateError,
    );
    expect(await db.select(db.decks).get(), isEmpty);
  });
  test(
    'foreign keys reject orphan notes and cascade dependent cards',
    () async {
      await expectLater(note(999), throwsA(isA<SqliteException>()));
      final deckId = await deck();
      final noteId = await note(deckId);
      await db
          .into(db.cards)
          .insert(CardsCompanion.insert(noteId: noteId, dueAtUtc: now));
      await (db.delete(db.decks)..where((row) => row.id.equals(deckId))).go();
      expect(await db.select(db.notes).get(), isEmpty);
      expect(await db.select(db.cards).get(), isEmpty);
    },
  );
  test('a note cannot generate duplicate basic or cloze cards', () async {
    final noteId = await note(await deck());
    final card = CardsCompanion.insert(noteId: noteId, dueAtUtc: now);
    await db.into(db.cards).insert(card);
    await expectLater(
      db.into(db.cards).insert(card),
      throwsA(isA<SqliteException>()),
    );
  });
}
