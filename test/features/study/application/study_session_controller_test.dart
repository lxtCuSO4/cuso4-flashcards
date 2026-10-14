import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/study/application/study_session_controller.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:cuso4_flashcards/features/study/domain/scheduler.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late StudyRepository repository;
  late StudySessionController session;
  late int deck;
  late DateTime now;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 15, 8);
    deck = await DeckRepository(db).createDeck('chemistry');
    final notes = NoteRepository(db);
    await notes.createBasicNote(deckId: deck, front: 'CuSO4', back: '硫酸铜');
    await notes.createClozeNote(deckId: deck, text: '硫酸铜晶体呈 {{c1::蓝色}}');
    await db
        .update(db.cards)
        .write(CardsCompanion(dueAtUtc: Value(now.millisecondsSinceEpoch)));
    repository = StudyRepository(
      db,
      clock: () => now,
      timezoneOffset: () => const Duration(hours: 8),
    );
    session = StudySessionController(repository, deckId: deck);
  });
  tearDown(() async {
    session.dispose();
    await db.close();
  });

  test(
    'answer gating and an async rating lock prevent duplicate submission',
    () async {
      await session.start();
      expect(session.current!.note.fields['front'], 'CuSO4');
      expect(session.answerVisible, isFalse);
      expect(session.previewIntervals, isEmpty);
      await session.rate(ReviewRating.easy);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      final before = session.current!.card.toJson();
      session.showAnswer();
      expect(session.previewIntervals.length, 4);
      expect(session.current!.card.toJson(), before);
      final rating = session.rate(ReviewRating.easy);
      await session.rate(ReviewRating.easy);
      await rating;
      expect((await db.select(db.reviewLogs).get()).length, 1);
      expect(session.completedReviews, 1);
      expect(session.current!.note.fields['text'], contains('{{c1::蓝色}}'));
      expect(session.answerVisible, isFalse);
      expect(session.canUndo, isTrue);
    },
  );

  test('undo restores the exact prior card and favorite does not change its schedule', () async {
    await session.start();
    final card = session.current!.card;
    session.showAnswer();
    await session.rate(ReviewRating.good);
    await session.undo();
    expect(session.current!.card.toJson(), card.toJson());
    expect(session.completedReviews, 0);
    expect(session.answerVisible, isFalse);
    expect(session.canUndo, isFalse);
    await session.toggleFavorite();
    expect(session.current!.card.isFavorite, isTrue);
    expect(session.current!.card.toJson(), card.toJson());
    expect(await db.select(db.reviewLogs).get(), isEmpty);
  });

  test('a failed grade retains the answer and card for a safe retry', () async {
    await session.start();
    final id = session.current!.card.id;
    await db.customStatement(
      "CREATE TRIGGER fail_review BEFORE INSERT ON review_logs BEGIN SELECT RAISE(FAIL, 'failure'); END",
    );
    session.showAnswer();
    await session.rate(ReviewRating.easy);
    expect(session.busy, isFalse);
    expect(session.error, isNotNull);
    expect(session.answerVisible, isTrue);
    expect(session.current!.card.id, id);
    expect(session.completedReviews, 0);
    await db.customStatement('DROP TRIGGER fail_review');
    await session.rate(ReviewRating.easy);
    expect(session.completedReviews, 1);
    expect(session.error, isNull);
  });

  test('completion means no currently eligible cards, not that future learning is erased', () async {
    await session.start();
    session.showAnswer();
    await session.rate(ReviewRating.good);
    session.showAnswer();
    await session.rate(ReviewRating.good);
    expect(session.isComplete, isTrue);
    expect(session.current, isNull);
    expect(session.completedReviews, 2);
    expect(
      (await db.select(db.cards).get()).every((c) => c.state == 1),
      isTrue,
    );
    now = now.add(const Duration(minutes: 10));
    await session.start();
    expect(session.isComplete, isFalse);
    expect(session.current, isNotNull);
  });
}
