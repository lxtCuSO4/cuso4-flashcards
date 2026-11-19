/// A read-only snapshot using stored option indexes and this attempt's letters.
class ChoiceAttemptSnapshot {
  ChoiceAttemptSnapshot({
    required Iterable<int> selected,
    required Iterable<int> order,
    required this.attempted,
  }) : selected = Set.unmodifiable(selected),
       order = List.unmodifiable(order);

  final Set<int> selected;
  final List<int> order;
  final bool attempted;

  String letters(Iterable<int> indexes) {
    final positions = indexes.map(order.indexOf).toList()..sort();
    return positions.map((i) => String.fromCharCode(65 + i)).join('、');
  }
}
