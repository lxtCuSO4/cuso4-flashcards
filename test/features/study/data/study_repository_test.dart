import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/flashcard.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:cuso4_flashcards/features/study/domain/scheduler.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late StudyRepository repository;
  late int root;
  late int child;
  late int other;
  late DateTime now;
  late Duration offset;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 15, 8);
    offset = const Duration(hours: 8);
    repository = StudyRepository(
      db,
      clock: () => now,
      timezoneOffset: () => offset,
      dailyNewLimit: 1,
      dailyReviewLimit: 1,
    );
    final decks = DeckRepository(db);
    root = await decks.createDeck('chemistry');
    child = await decks.createDeck('inorganic', parentId: root);
    other = await decks.createDeck('other');
  });
  tearDown(() => db.close());

  Future<Flashcard> create(
    int deck, {
    CardState state = CardState.newCard,
  }) async {
    final note = await NoteRepository(db)
        .createBasicNote(deckId: deck, front: 'CuSO4', back: '硫酸铜');
    final row = (await (db.select(
      db.cards,
    )..where((c) => c.noteId.equals(note))).get()).single;
    await (db.update(db.cards)..where((c) => c.id.equals(row.id))).write(
      CardsCompanion(
        state: Value(state.index),
        dueAtUtc: Value(
          now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
        ),
        repetitions: Value(state == CardState.newCard ? 0 : 3),
        stability: Value(state == CardState.newCard ? null : 12.0),
        difficulty: Value(state == CardState.newCard ? null : 5.0),
        lastReviewAtUtc: Value(
          state == CardState.newCard
              ? null
              : now.subtract(const Duration(days: 14)).millisecondsSinceEpoch,
        ),
      ),
    );
    return repository.getCard(row.id);
  }

  test(
    'queue is bounded, includes descendants and orders review, learning, new',
    () async {
      final fresh = await create(child);
      final learning = await create(child, state: CardState.learning);
      final review = await create(root, state: CardState.review);
      await create(other, state: CardState.review);
      final queue = await repository.loadQueue(deckId: root);
      expect(queue.map((c) => c.id), [review.id, learning.id, fresh.id]);
      expect((await repository.loadQueue(deckId: root, limit: 2)).length, 2);
    },
  );

  test(
    'rating and log are atomic and undo preserves a later favorite action',
    () async {
      final card = await create(child);
      final receipt = await repository.rateCard(
        card,
        ReviewRating.good,
        elapsed: const Duration(seconds: 3),
      );
      final stored = await repository.getCard(card.id);
      expect(stored.toJson(), receipt.after.toJson());
      final log = (await db.select(db.reviewLogs).get()).single;
      expect(log.elapsedMilliseconds, 3000);
      expect(log.rating, 3);
      expect(log.reviewedAtUtc, now.millisecondsSinceEpoch);
      await repository.setFavorite(card.id, true);
      expect((await repository.getCard(card.id)).dueAtUtc, stored.dueAtUtc);
      await repository.undoReview(receipt.logId);
      expect((await repository.getCard(card.id)).toJson(), card.toJson());
      expect((await repository.getCard(card.id)).isFavorite, isTrue);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
    },
  );

  test(
    'a failed review-log insert rolls back the scheduler and quota',
    () async {
      final card = await create(child);
      await db.customStatement(
        "CREATE TRIGGER fail_review BEFORE INSERT ON review_logs BEGIN SELECT RAISE(FAIL, 'failure'); END",
      );
      await expectLater(
        repository.rateCard(card, ReviewRating.easy),
        throwsA(anything),
      );
      expect((await repository.getCard(card.id)).toJson(), card.toJson());
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      expect((await repository.loadQueue(deckId: child)).single.id, card.id);
    },
  );

  test(
    'stale repeated ratings and non-latest undo cannot corrupt history',
    () async {
      final first = await create(child);
      final second = await create(other);
      final receipt = await repository.rateCard(first, ReviewRating.easy);
      await expectLater(
        repository.rateCard(first, ReviewRating.easy),
        throwsStateError,
      );
      final secondReceipt = await repository.rateCard(
        second,
        ReviewRating.easy,
      );
      await expectLater(repository.undoReview(receipt.logId), throwsStateError);
      expect((await db.select(db.reviewLogs).get()).length, 2);
      await repository.undoReview(secondReceipt.logId);
      expect(
        (await repository.getCard(first.id)).toJson(),
        receipt.after.toJson(),
      );
    },
  );

  test('each deck has its own daily new limit, checked again when rating cached cards', () async {
    final first = await create(child);
    final second = await create(child);
    final separate = await create(other);
    expect(
      (await repository.loadQueue())
          .where((c) => c.state == CardState.newCard)
          .map((c) => c.id)
          .toSet(),
      {first.id, separate.id},
    );
    final receipt = await repository.rateCard(first, ReviewRating.easy);
    expect((await repository.loadQueue(deckId: child)), isEmpty);
    await expectLater(
      repository.rateCard(second, ReviewRating.good),
      throwsStateError,
    );
    expect((await repository.loadQueue(deckId: other)).single.id, separate.id);
    await repository.undoReview(receipt.logId);
    expect((await repository.loadQueue(deckId: child)).single.id, first.id);
  });

  test('review limits do not block due learning cards', () async {
    final review = await create(child, state: CardState.review);
    final secondReview = await create(child, state: CardState.review);
    final learning = await create(child, state: CardState.learning);
    await repository.rateCard(review, ReviewRating.easy);
    expect((await repository.loadQueue(deckId: child)).map((c) => c.id), [
      learning.id,
    ]);
    await expectLater(
      repository.rateCard(secondReview, ReviewRating.good),
      throwsStateError,
    );
  });

  test(
    'midnight resets the quota but device timezone changes do not',
    () async {
      now = DateTime.utc(
        2026,
        10,
        15,
        15,
        59,
      ); // 23:59 at the initially pinned +08:00 offset.
      final first = await create(child);
      final second = await create(child);
      await repository.loadQueue(deckId: child);
      await repository.rateCard(first, ReviewRating.easy);
      offset = const Duration(
        hours: -8,
      ); // Traveling must not grant another batch.
      final reopened = StudyRepository(
        db,
        clock: () => now,
        timezoneOffset: () => offset,
        dailyNewLimit: 1,
      );
      expect(await reopened.loadQueue(deckId: child), isEmpty);
      now = DateTime.utc(
        2026,
        10,
        15,
        16,
      ); // The pinned learning day just changed.
      expect((await reopened.loadQueue(deckId: child)).single.id, second.id);
    },
  );

  test(
    'moving a reviewed note does not move its already-consumed daily quota',
    () async {
      final first = await create(child);
      final remaining = await create(child);
      await repository.rateCard(first, ReviewRating.easy);
      await (db.update(db.notes)..where((n) => n.id.equals(first.noteId)))
          .write(NotesCompanion(deckId: Value(other)));
      expect(await repository.loadQueue(deckId: child), isEmpty);
      await expectLater(
        repository.rateCard(remaining, ReviewRating.good),
        throwsStateError,
      );
    },
  );

  test(
    'a failed undo-log delete restores neither half of the transaction',
    () async {
      final card = await create(child);
      final receipt = await repository.rateCard(card, ReviewRating.easy);
      await db.customStatement(
        "CREATE TRIGGER fail_undo BEFORE DELETE ON review_logs BEGIN SELECT RAISE(FAIL, 'failure'); END",
      );
      await expectLater(
        repository.undoReview(receipt.logId),
        throwsA(anything),
      );
      expect(
        (await repository.getCard(card.id)).toJson(),
        receipt.after.toJson(),
      );
      expect((await db.select(db.reviewLogs).get()).single.id, receipt.logId);
    },
  );

  test(
    'future cards are excluded and cannot be rated ahead of their due time',
    () async {
      final card = await create(child, state: CardState.learning);
      await (db.update(db.cards)..where((c) => c.id.equals(card.id))).write(
        CardsCompanion(
          dueAtUtc: Value(
            now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
          ),
        ),
      );
      final future = await repository.getCard(card.id);
      expect(await repository.loadQueue(deckId: child), isEmpty);
      await expectLater(
        repository.rateCard(future, ReviewRating.good),
        throwsStateError,
      );
      expect(await db.select(db.reviewLogs).get(), isEmpty);
    },
  );

  test(
    'two concurrent sessions can commit only one review of the same snapshot',
    () async {
      final card = await create(child);
      Future<bool> attempt() async {
        try {
          await repository.rateCard(card, ReviewRating.easy);
          return true;
        } on StateError {
          return false;
        }
      }

      final results = await Future.wait([attempt(), attempt()]);
      expect(results.where((succeeded) => succeeded).length, 1);
      expect((await db.select(db.reviewLogs).get()).length, 1);
      expect((await repository.getCard(card.id)).repetitions, 1);
    },
  );
}
