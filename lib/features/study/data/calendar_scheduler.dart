import '../../decks/domain/flashcard.dart';
import '../../settings/domain/study_settings.dart';
import '../domain/scheduler.dart';
import 'fsrs_scheduler.dart';

/// A fixed policy over the existing memory state, using the same pinned
/// learning-day offset as daily quotas. It makes no retention prediction.
class CalendarScheduler implements Scheduler {
  CalendarScheduler(this.settings, {required this.offsetMinutes})
    : _memory = FsrsScheduler(desiredRetention: settings.desiredRetention);

  final StudySettings settings;
  final FsrsScheduler _memory;
  int offsetMinutes;

  @override
  double get desiredRetention => _memory.desiredRetention;

  DateTime dayAt(DateTime utc) {
    final shifted = utc.toUtc().add(Duration(minutes: offsetMinutes));
    return DateTime.utc(shifted.year, shifted.month, shifted.day);
  }

  DateTime dueFor(ReviewRating rating, DateTime reviewedAtUtc) {
    final now = reviewedAtUtc.toUtc();
    if (rating == ReviewRating.again) {
      return now.add(Duration(minutes: settings.againMinutes));
    }
    final days = switch (rating) {
      ReviewRating.hard => settings.hardDays,
      ReviewRating.good => settings.goodDays,
      ReviewRating.easy => settings.easyDays,
      ReviewRating.again => throw StateError('分钟间隔已单独处理'),
    };
    final day = dayAt(now);
    return DateTime.utc(
      day.year,
      day.month,
      day.day + days,
    ).subtract(Duration(minutes: offsetMinutes));
  }

  Map<ReviewRating, String> previewLabels(DateTime reviewedAtUtc) => {
    for (final rating in ReviewRating.values.where(
      (r) => r != ReviewRating.again,
    ))
      rating: _dateLabel(rating, reviewedAtUtc),
  };

  String _dateLabel(ReviewRating rating, DateTime now) {
    final date = dueFor(rating, now).add(Duration(minutes: offsetMinutes));
    final days = dayAt(dueFor(rating, now)).difference(dayAt(now)).inDays;
    final label = days == 1 ? '明天' : '$days 天后';
    final year = date.year == dayAt(now).year ? '' : '${date.year}/';
    return '$label · $year${date.month}/${date.day}';
  }

  @override
  Map<ReviewRating, Duration> previewIntervals(
    Flashcard card, {
    required DateTime reviewedAtUtc,
  }) {
    // Validate the source just as actual scoring does.
    return Map.unmodifiable({
      for (final rating in ReviewRating.values)
        rating: applyReview(
          card,
          rating,
          reviewedAtUtc: reviewedAtUtc,
        ).dueAtUtc.difference(reviewedAtUtc.toUtc()),
    });
  }

  @override
  Flashcard applyReview(
    Flashcard card,
    ReviewRating rating, {
    required DateTime reviewedAtUtc,
  }) {
    final updated = _memory.applyReview(
      card,
      rating,
      reviewedAtUtc: reviewedAtUtc,
    );
    final again = rating == ReviewRating.again;
    return Flashcard(
      id: updated.id,
      noteId: updated.noteId,
      clozeIndex: updated.clozeIndex,
      dueAtUtc: dueFor(rating, reviewedAtUtc),
      state: !again
          ? CardState.review
          : card.state == CardState.newCard || card.state == CardState.learning
          ? CardState.learning
          : CardState.relearning,
      stability: updated.stability,
      difficulty: updated.difficulty,
      learningStep: 0,
      repetitions: updated.repetitions,
      lapses: updated.lapses,
      lastReviewAtUtc: updated.lastReviewAtUtc,
      isFavorite: updated.isFavorite,
    );
  }
}
