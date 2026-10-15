import '../../study/domain/study_availability.dart';

class HomeDeckSummary {
  const HomeDeckSummary({
    required this.id,
    required this.name,
    required this.cardCount,
  });
  final int id;
  final String name;
  final int cardCount; // Includes descendant chapters.
}

class HomeSummary {
  const HomeSummary({
    required this.availability,
    required this.studiedCards,
    required this.ratingCount,
    required this.streak,
    required this.deckCount,
    required this.decks,
  });
  final StudyAvailability availability;
  final int studiedCards;
  final int ratingCount;
  final int streak;
  final int deckCount; // Includes child decks.
  final List<HomeDeckSummary> decks; // Up to five root decks.
}
