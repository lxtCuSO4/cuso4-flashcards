import '../../decks/domain/flashcard.dart';

enum ReviewRating {
  again(1, '重来'),
  hard(2, '困难'),
  good(3, '良好'),
  easy(4, '简单');

  const ReviewRating(this.value, this.label);
  final int value;
  final String label;
}

abstract interface class Scheduler {
  double get desiredRetention;
  Map<ReviewRating, Duration> previewIntervals(
    Flashcard card, {
    required DateTime reviewedAtUtc,
  });
  Flashcard applyReview(
    Flashcard card,
    ReviewRating rating, {
    required DateTime reviewedAtUtc,
  });
}
