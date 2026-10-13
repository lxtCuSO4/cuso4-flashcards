enum CardState { newCard, learning, review, relearning }

class Flashcard {
  Flashcard({
    required this.id,
    required this.noteId,
    required DateTime dueAtUtc,
    this.clozeIndex,
    this.state = CardState.newCard,
    this.stability,
    this.difficulty,
    this.learningStep = 0,
    this.repetitions = 0,
    this.lapses = 0,
    this.isFavorite = false,
    DateTime? lastReviewAtUtc,
  }) : dueAtUtc = dueAtUtc.toUtc(),
       lastReviewAtUtc = lastReviewAtUtc?.toUtc();

  final int id;
  final int noteId;
  final int? clozeIndex;
  final DateTime dueAtUtc;
  final CardState state;
  final double? stability;
  final double? difficulty;
  final int learningStep;
  final int repetitions;
  final int lapses;
  final bool isFavorite;
  final DateTime? lastReviewAtUtc;
}
