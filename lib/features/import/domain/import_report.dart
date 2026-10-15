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
    this.singleChoice = 0,
    this.multipleChoice = 0,
    this.choiceFallback = 0,
  });
  final int decks;
  final int notes;
  final int cards;
  final int media;
  final int skipped;
  final Map<String, int> skippedReasons;
  final int missingMedia;
  final int unsupportedMedia;
  final int singleChoice;
  final int multipleChoice;
  final int choiceFallback;

  Map<String, Object> toJson() => {
    'decks': decks,
    'notes': notes,
    'cards': cards,
    'media': media,
    'skipped': skipped,
    'skippedReasons': skippedReasons,
    'missingMedia': missingMedia,
    'unsupportedMedia': unsupportedMedia,
    'singleChoice': singleChoice,
    'multipleChoice': multipleChoice,
    'choiceFallback': choiceFallback,
  };
}
