import '../../decks/domain/flashcard.dart';
import '../../decks/domain/note.dart';

class StudyCard {
  const StudyCard({
    required this.card,
    required this.note,
    required this.deckName,
  });
  final Flashcard card;
  final Note note;
  final String deckName;
}

class ReviewReceipt {
  const ReviewReceipt({
    required this.logId,
    required this.before,
    required this.after,
  });
  final int logId;
  final Flashcard before;
  final Flashcard after;
}
