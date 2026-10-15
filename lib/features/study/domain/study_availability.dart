/// Read-only view of the same eligible cards used by the study queue.
class StudyAvailability {
  const StudyAvailability({
    required this.today,
    required this.dayStartUtc,
    required this.dayEndUtc,
    required this.offsetMinutes,
    required this.newCards,
    required this.reviews,
    required this.learning,
    required this.blockedNewCards,
    required this.blockedReviews,
    required this.totalCards,
    required this.nextDueAtUtc,
  });

  final DateTime today; // Calendar date represented at UTC midnight.
  final DateTime dayStartUtc;
  final DateTime dayEndUtc;
  final int offsetMinutes;
  final int newCards;
  final int reviews;
  final int learning;
  final int blockedNewCards;
  final int blockedReviews;
  final int totalCards;
  final DateTime? nextDueAtUtc;
  int get availableCards => newCards + reviews + learning;
  int get blockedCards => blockedNewCards + blockedReviews;
  DateTime get refreshAtUtc =>
      nextDueAtUtc != null && nextDueAtUtc!.isBefore(dayEndUtc)
      ? nextDueAtUtc!
      : dayEndUtc;
}
