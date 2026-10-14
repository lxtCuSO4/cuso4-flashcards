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

  /// Versioned UTC millisecond snapshot. Favorites live in their own table and
  /// are deliberately excluded, so undo never changes a later favorite action.
  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'noteId': noteId,
    'clozeIndex': clozeIndex,
    'dueAtUtc': dueAtUtc.millisecondsSinceEpoch,
    'state': state.index,
    'stability': stability,
    'difficulty': difficulty,
    'learningStep': learningStep,
    'repetitions': repetitions,
    'lapses': lapses,
    'lastReviewAtUtc': lastReviewAtUtc?.millisecondsSinceEpoch,
  };

  factory Flashcard.fromJson(Map<String, dynamic> json) {
    if (json['version'] != 1) throw const FormatException('不支持的排程快照版本');
    return Flashcard(
      id: json['id'] as int,
      noteId: json['noteId'] as int,
      clozeIndex: json['clozeIndex'] as int?,
      dueAtUtc: DateTime.fromMillisecondsSinceEpoch(
        json['dueAtUtc'] as int,
        isUtc: true,
      ),
      state: CardState.values[json['state'] as int],
      stability: (json['stability'] as num?)?.toDouble(),
      difficulty: (json['difficulty'] as num?)?.toDouble(),
      learningStep: json['learningStep'] as int,
      repetitions: json['repetitions'] as int,
      lapses: json['lapses'] as int,
      lastReviewAtUtc: json['lastReviewAtUtc'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              json['lastReviewAtUtc'] as int,
              isUtc: true,
            ),
    );
  }
}
