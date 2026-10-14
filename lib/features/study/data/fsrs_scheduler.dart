import 'package:fsrs/fsrs.dart' as fsrs;

import '../../decks/domain/flashcard.dart';
import '../domain/scheduler.dart';

/// Package-specific types never escape this adapter. Fuzzing is disabled so
/// previews and reviews at the same instant always produce the same interval.
class FsrsScheduler implements Scheduler {
  FsrsScheduler({this.desiredRetention = 0.9}) {
    if (!desiredRetention.isFinite ||
        desiredRetention <= 0 ||
        desiredRetention >= 1) {
      throw ArgumentError('期望记忆保持率必须大于 0 且小于 1');
    }
    _scheduler = fsrs.Scheduler(
      desiredRetention: desiredRetention,
      enableFuzzing: false,
    );
  }
  @override
  final double desiredRetention;
  late final fsrs.Scheduler _scheduler;

  @override
  Map<ReviewRating, Duration> previewIntervals(
    Flashcard card, {
    required DateTime reviewedAtUtc,
  }) => Map.unmodifiable({
    for (final rating in ReviewRating.values)
      rating: applyReview(
        card,
        rating,
        reviewedAtUtc: reviewedAtUtc,
      ).dueAtUtc.difference(reviewedAtUtc.toUtc()),
  });

  @override
  Flashcard applyReview(
    Flashcard card,
    ReviewRating rating, {
    required DateTime reviewedAtUtc,
  }) {
    final now = reviewedAtUtc.toUtc();
    _validate(card, now);
    final source = fsrs.Card(
      cardId: card.id,
      state: card.state == CardState.newCard
          ? fsrs.State.learning
          : fsrs.State.fromValue(card.state.index),
      step: card.state == CardState.review ? null : card.learningStep,
      stability: card.stability,
      difficulty: card.difficulty,
      due: card.dueAtUtc,
      lastReview: card.lastReviewAtUtc,
    );
    final result = _scheduler
        .reviewCard(
          source,
          fsrs.Rating.fromValue(rating.value),
          reviewDateTime: now,
        )
        .card;
    return Flashcard(
      id: card.id,
      noteId: card.noteId,
      clozeIndex: card.clozeIndex,
      state: CardState.values[result.state.value],
      dueAtUtc: result.due,
      stability: result.stability,
      difficulty: result.difficulty,
      learningStep: result.step ?? 0,
      repetitions: card.repetitions + 1,
      lapses:
          card.lapses +
          (card.state == CardState.review && rating == ReviewRating.again
              ? 1
              : 0),
      lastReviewAtUtc: result.lastReview,
      isFavorite: card.isFavorite,
    );
  }

  void _validate(Flashcard card, DateTime now) {
    if (card.repetitions < 0 ||
        card.lapses < 0 ||
        card.learningStep < 0 ||
        (card.lastReviewAtUtc != null && now.isBefore(card.lastReviewAtUtc!))) {
      throw ArgumentError('卡片排程无效或系统时间早于上次复习');
    }
    if (card.state == CardState.newCard) {
      if (card.stability != null ||
          card.difficulty != null ||
          card.lastReviewAtUtc != null ||
          card.repetitions != 0) {
        throw ArgumentError('新卡不能包含已有的复习排程');
      }
    } else if (card.stability == null ||
        !card.stability!.isFinite ||
        card.stability! <= 0 ||
        card.difficulty == null ||
        !card.difficulty!.isFinite ||
        card.difficulty! < 1 ||
        card.difficulty! > 10 ||
        card.lastReviewAtUtc == null) {
      throw ArgumentError('卡片缺少有效的 FSRS 状态');
    }
  }
}
