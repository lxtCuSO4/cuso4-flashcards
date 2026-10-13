class ImportReport {
  const ImportReport({
    required this.decks,
    required this.notes,
    required this.cards,
    required this.media,
    this.skipped = 0,
    this.skippedReasons = const {},
    this.missingMedia = 0,
    this.unsupportedMedia = 0,
  });
  final int decks;
  final int notes;
  final int cards;
  final int media;
  final int skipped;
  final Map<String, int> skippedReasons;
  final int missingMedia;
  final int unsupportedMedia;
}
