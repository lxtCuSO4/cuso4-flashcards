enum NoteType { basic, cloze }

class Note {
  Note({
    required this.id,
    required this.deckId,
    required this.type,
    required Map<String, String> fields,
    required Iterable<String> tags,
    required DateTime createdAtUtc,
    required DateTime modifiedAtUtc,
  }) : fields = Map.unmodifiable(fields),
       tags = List.unmodifiable(tags),
       createdAtUtc = createdAtUtc.toUtc(),
       modifiedAtUtc = modifiedAtUtc.toUtc();

  final int id;
  final int deckId;
  final NoteType type;
  final Map<String, String> fields;
  final List<String> tags;
  final DateTime createdAtUtc;
  final DateTime modifiedAtUtc;
}
