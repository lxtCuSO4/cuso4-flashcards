import 'dart:convert';

import 'package:cuso4_flashcards/features/decks/domain/flashcard.dart';
import 'package:cuso4_flashcards/features/study/data/fsrs_scheduler.dart';
import 'package:cuso4_flashcards/features/study/domain/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 15, 9);
  Flashcard fresh() => Flashcard(id: 1, noteId: 2, dueAtUtc: now);

  test(
    'new-card previews are ordered and match deterministic actual reviews',
    () {
      final Scheduler scheduler = FsrsScheduler();
      expect(scheduler.desiredRetention, 0.9);
      final card = fresh();
      final before = card.toJson();
      final previews = scheduler.previewIntervals(card, reviewedAtUtc: now);
      expect(previews[ReviewRating.again], const Duration(minutes: 1));
      expect(previews[ReviewRating.good], const Duration(minutes: 10));
      final intervals = ReviewRating.values
          .map((r) => previews[r]!.inSeconds)
          .toList();
      for (var i = 1; i < intervals.length; i++) {
        expect(intervals[i], greaterThan(intervals[i - 1]));
      }
      for (final rating in ReviewRating.values) {
        final result = scheduler.applyReview(card, rating, reviewedAtUtc: now);
        expect(result.dueAtUtc.difference(now), previews[rating]);
        expect(result.dueAtUtc.isUtc, isTrue);
        expect(result.lastReviewAtUtc, now);
        expect(
          result.toJson(),
          scheduler.applyReview(card, rating, reviewedAtUtc: now).toJson(),
        );
        expect(result.repetitions, 1);
        expect(result.lapses, 0);
      }
      expect(card.toJson(), before);
    },
  );

  test(
    'mature reviews use all four ratings and forgetting starts relearning',
    () {
      final card = Flashcard(
        id: 1,
        noteId: 2,
        clozeIndex: 3,
        dueAtUtc: now,
        state: CardState.review,
        stability: 12,
        difficulty: 5,
        repetitions: 7,
        lapses: 2,
        lastReviewAtUtc: now.subtract(const Duration(days: 15)),
      );
      final scheduler = FsrsScheduler();
      final previews = scheduler.previewIntervals(card, reviewedAtUtc: now);
      final again = scheduler.applyReview(
        card,
        ReviewRating.again,
        reviewedAtUtc: now,
      );
      expect(again.state, CardState.relearning);
      expect(again.learningStep, 0);
      expect(again.lapses, 3);
      expect(again.repetitions, 8);
      expect(again.clozeIndex, 3);
      expect(previews[ReviewRating.again], const Duration(minutes: 10));
      final ordered = ReviewRating.values
          .map((r) => previews[r]!.inSeconds)
          .toList();
      for (var i = 1; i < ordered.length; i++) {
        expect(ordered[i], greaterThan(ordered[i - 1]));
      }
      final relearned = scheduler.applyReview(
        again,
        ReviewRating.good,
        reviewedAtUtc: again.dueAtUtc,
      );
      expect(relearned.state, CardState.review);
      expect(relearned.lapses, 3);
    },
  );

  test('new cards follow the two learning steps before graduation', () {
    final scheduler = FsrsScheduler();
    final learning = scheduler.applyReview(
      fresh(),
      ReviewRating.good,
      reviewedAtUtc: now,
    );
    expect(learning.state, CardState.learning);
    expect(learning.learningStep, 1);
    final graduated = scheduler.applyReview(
      learning,
      ReviewRating.good,
      reviewedAtUtc: learning.dueAtUtc,
    );
    expect(graduated.state, CardState.review);
    expect(graduated.learningStep, 0);
    expect(graduated.dueAtUtc.isAfter(learning.dueAtUtc), isTrue);
  });

  test(
    'scheduler snapshots round trip without losing precision or identity',
    () {
      final card = FsrsScheduler().applyReview(
        fresh(),
        ReviewRating.easy,
        reviewedAtUtc: now,
      );
      final restored = Flashcard.fromJson(
        jsonDecode(jsonEncode(card.toJson())) as Map<String, dynamic>,
      );
      expect(restored.toJson(), card.toJson());
      expect(restored.dueAtUtc.isUtc, isTrue);
      expect(Flashcard.fromJson(fresh().toJson()).state, CardState.newCard);
    },
  );

  test('retention rejects non-finite values and endpoints', () {
    for (final retention in [
      0.0,
      1.0,
      -0.1,
      1.1,
      double.nan,
      double.infinity,
    ]) {
      expect(
        () => FsrsScheduler(desiredRetention: retention),
        throwsArgumentError,
      );
    }
    final lower = FsrsScheduler(desiredRetention: 0.8)
        .applyReview(fresh(), ReviewRating.easy, reviewedAtUtc: now);
    final higher = FsrsScheduler(desiredRetention: 0.95)
        .applyReview(fresh(), ReviewRating.easy, reviewedAtUtc: now);
    expect(higher.dueAtUtc.isBefore(lower.dueAtUtc), isTrue);
  });

  test(
    'invalid state or a backwards review clock is rejected before mutation',
    () {
      final scheduler = FsrsScheduler();
      final reviewed = scheduler.applyReview(
        fresh(),
        ReviewRating.good,
        reviewedAtUtc: now,
      );
      expect(
        () => scheduler.applyReview(
          reviewed,
          ReviewRating.good,
          reviewedAtUtc: now.subtract(const Duration(seconds: 1)),
        ),
        throwsArgumentError,
      );
      final invalid = Flashcard(
        id: 1,
        noteId: 2,
        dueAtUtc: now,
        state: CardState.review,
      );
      expect(
        () => scheduler.previewIntervals(invalid, reviewedAtUtc: now),
        throwsArgumentError,
      );
    },
  );
}
