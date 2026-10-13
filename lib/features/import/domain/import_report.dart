class ImportReport {
  const ImportReport({
    required this.decks,
    required this.notes,
    required this.cards,
    required this.media,
    this.skipped = 0,
    this.skippedReasons = const {},
  });
  final int decks;
  final int notes;
  final int cards;
  final int media;
  final int skipped;
  final Map<String, int> skippedReasons;
}
