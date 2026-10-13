class Deck {
  Deck({
    required this.id,
    required this.name,
    required DateTime createdAtUtc,
    required DateTime modifiedAtUtc,
    this.parentId,
  }) : createdAtUtc = createdAtUtc.toUtc(),
       modifiedAtUtc = modifiedAtUtc.toUtc();

  final int id;
  final int? parentId;
  final String name;
  final DateTime createdAtUtc;
  final DateTime modifiedAtUtc;
}
