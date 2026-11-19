import '../../decks/domain/choice_attempt.dart';

enum PracticeOrder { random, sequential }

class PracticeRound {
  PracticeRound({
    required this.deckName,
    required Iterable<int> cardIds,
    this.legacyBefore = 0,
  }) : cardIds = List.unmodifiable(cardIds);
  final String deckName;
  final List<int> cardIds;
  final int legacyBefore;
}

class PracticeScope {
  const PracticeScope({
    this.deckId,
    this.includeChildren = true,
    this.favoritesOnly = false,
    this.choicesOnly = false,
    this.wrongOnly = false,
    this.order = PracticeOrder.random,
  });
  final int? deckId;
  final bool includeChildren, favoritesOnly, choicesOnly, wrongOnly;
  final PracticeOrder order;
  String get entryKey =>
      '${deckId ?? 'all'}:${favoritesOnly ? 1 : 0}:${choicesOnly ? 1 : 0}:${wrongOnly ? 1 : 0}';
  String get key =>
      'practice:v1:$entryKey:${includeChildren ? 1 : 0}:${order.name}';
}

/// A durable round snapshot. Queues are stored once; only this small cursor
/// changes while answering. None of these fields are FSRS review records.
class PracticeSession {
  PracticeSession({
    required this.scope,
    required this.id,
    required this.round,
    this.index = 0,
    this.skipped = 0,
    this.correct = 0,
    this.incorrect = 0,
    this.unanswered = 0,
    this.completed = false,
    this.signature = '',
    this.isChoice = false,
    Iterable<int> order = const [],
    Iterable<int> selected = const [],
    this.attempted = false,
    this.answerVisible = false,
    this.explanation = false,
    this.currentCorrect = -1,
    this.settled = false,
    this.wasSkipped = false,
    this.roundFinished = false,
    this.legacyReview = false,
    this.elapsedMs = 0,
    this.generation = 0,
  }) : optionOrder = List.unmodifiable(order),
       selected = Set.unmodifiable(selected);

  final PracticeScope scope;
  final String id;
  final PracticeRound round;
  final int index, skipped, correct, incorrect, unanswered;
  final bool completed;
  final String signature;
  final bool isChoice, attempted, answerVisible, explanation;
  final List<int> optionOrder;
  final Set<int> selected;
  final int currentCorrect;
  final bool settled, wasSkipped, roundFinished, legacyReview;
  final int elapsedMs, generation;
  int? get cardId =>
      completed || index >= round.cardIds.length ? null : round.cardIds[index];
  ChoiceAttemptSnapshot? get attempt => optionOrder.isEmpty
      ? null
      : ChoiceAttemptSnapshot(
          selected: selected,
          order: optionOrder,
          attempted: attempted,
        );

  PracticeSession copyWith({
    int? index,
    int? skipped,
    int? correct,
    int? incorrect,
    int? unanswered,
    bool? completed,
    String? signature,
    bool? isChoice,
    Iterable<int>? order,
    Iterable<int>? selected,
    bool? attempted,
    bool? answerVisible,
    bool? explanation,
    int? currentCorrect,
    bool resetCard = false,
    bool? settled,
    bool? wasSkipped,
    bool? roundFinished,
    bool? legacyReview,
    int? elapsedMs,
    int? generation,
  }) => PracticeSession(
    scope: scope,
    id: id,
    round: round,
    index: index ?? this.index,
    skipped: skipped ?? this.skipped,
    correct: correct ?? this.correct,
    incorrect: incorrect ?? this.incorrect,
    unanswered: unanswered ?? this.unanswered,
    completed: completed ?? this.completed,
    signature: signature ?? (resetCard ? '' : this.signature),
    isChoice: isChoice ?? (!resetCard && this.isChoice),
    order: order ?? (resetCard ? const [] : optionOrder),
    selected: selected ?? (resetCard ? const [] : this.selected),
    attempted: attempted ?? (!resetCard && this.attempted),
    answerVisible: answerVisible ?? (!resetCard && this.answerVisible),
    explanation: explanation ?? (!resetCard && this.explanation),
    currentCorrect: currentCorrect ?? (resetCard ? -1 : this.currentCorrect),
    settled: settled ?? (!resetCard && this.settled),
    wasSkipped: wasSkipped ?? (!resetCard && this.wasSkipped),
    roundFinished: roundFinished ?? this.roundFinished,
    legacyReview: legacyReview ?? (!resetCard && this.legacyReview),
    elapsedMs: elapsedMs ?? (resetCard ? 0 : this.elapsedMs),
    generation: generation ?? (resetCard ? 0 : this.generation),
  );

  Map<String, Object> get cursor => {
    'version': 2,
    'id': id,
    'index': index,
    'skipped': skipped,
    'correct': correct,
    'incorrect': incorrect,
    'unanswered': unanswered,
    'completed': completed,
    'signature': signature,
    'isChoice': isChoice,
    'order': optionOrder,
    'selected': selected.toList(),
    'attempted': attempted,
    'answerVisible': answerVisible,
    'explanation': explanation,
    'currentCorrect': currentCorrect,
    'settled': settled,
    'wasSkipped': wasSkipped,
    'roundFinished': roundFinished,
    'legacyReview': legacyReview,
    'elapsedMs': elapsedMs,
    'generation': generation,
  };

  factory PracticeSession.decode(
    PracticeScope scope,
    Map<String, dynamic> queue,
    Map<String, dynamic> cursor,
  ) {
    final ids = (queue['cardIds'] as List).cast<int>();
    final index = cursor['index'] as int;
    final completed = cursor['completed'] as bool;
    final order = (cursor['order'] as List).cast<int>();
    final selected = (cursor['selected'] as List).cast<int>();
    if (![1, 2].contains(queue['version']) ||
        ![1, 2].contains(cursor['version']) ||
        queue['id'] is! String ||
        queue['id'] != cursor['id'] ||
        ids.any((v) => v <= 0) ||
        ids.toSet().length != ids.length ||
        index < 0 ||
        index > ids.length ||
        (!completed && index == ids.length) ||
        order.toSet().length != order.length ||
        order.any((v) => v < 0 || v >= order.length) ||
        selected.any((v) => !order.contains(v)) ||
        [
          'skipped',
          'correct',
          'incorrect',
          'unanswered',
        ].any((key) => cursor[key] is! int || (cursor[key] as int) < 0) ||
        ![-1, 0, 1].contains(cursor['currentCorrect'])) {
      throw const FormatException('Invalid practice cursor');
    }
    return PracticeSession(
      scope: scope,
      id: queue['id'] as String,
      round: PracticeRound(
        deckName: queue['deckName'] as String,
        cardIds: ids,
        legacyBefore: (queue['legacyBefore'] as int?) ?? 0,
      ),
      index: index,
      completed: completed,
      skipped: cursor['skipped'] as int,
      correct: cursor['correct'] as int,
      incorrect: cursor['incorrect'] as int,
      unanswered: cursor['unanswered'] as int,
      signature: cursor['signature'] as String,
      isChoice: cursor['isChoice'] as bool,
      order: order,
      selected: selected,
      attempted: cursor['attempted'] as bool,
      answerVisible: cursor['answerVisible'] as bool,
      explanation: cursor['explanation'] as bool,
      currentCorrect: cursor['currentCorrect'] as int,
      settled: (cursor['settled'] as bool?) ?? cursor['attempted'] == true,
      wasSkipped: (cursor['wasSkipped'] as bool?) ?? false,
      roundFinished: (cursor['roundFinished'] as bool?) ?? completed,
      legacyReview: (cursor['legacyReview'] as bool?) ?? false,
      elapsedMs: (cursor['elapsedMs'] as int?) ?? 0,
      generation: (cursor['generation'] as int?) ?? 0,
    );
  }
}

enum PracticeAnswerStatus { pending, viewed, correct, wrong, skipped, legacy }

class PracticeAnswer {
  const PracticeAnswer(
    this.cardId,
    this.index,
    this.status, {
    this.favorite = false,
  });
  final int cardId, index;
  final PracticeAnswerStatus status;
  final bool favorite;
  String get label => switch (status) {
    PracticeAnswerStatus.pending => '未答',
    PracticeAnswerStatus.viewed => '已看答案',
    PracticeAnswerStatus.correct => '答对',
    PracticeAnswerStatus.wrong => '答错',
    PracticeAnswerStatus.skipped => '已跳过',
    PracticeAnswerStatus.legacy => '已练习（旧版无答案记录）',
  };
}
