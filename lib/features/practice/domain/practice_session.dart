import '../../decks/domain/choice_attempt.dart';

enum PracticeOrder { random, sequential }

class PracticeRound {
  PracticeRound({required this.deckName, required Iterable<int> cardIds})
    : cardIds = List.unmodifiable(cardIds);
  final String deckName;
  final List<int> cardIds;
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
  );

  Map<String, Object> get cursor => {
    'version': 1,
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
    if (queue['version'] != 1 ||
        cursor['version'] != 1 ||
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
      round: PracticeRound(deckName: queue['deckName'] as String, cardIds: ids),
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
    );
  }
}
