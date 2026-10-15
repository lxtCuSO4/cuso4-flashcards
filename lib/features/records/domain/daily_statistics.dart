enum StatisticsPeriod {
  week('7 天', 7),
  month('30 天', 30),
  quarter('90 天', 90),
  all('全部', null);

  const StatisticsPeriod(this.label, this.days);
  final String label;
  final int? days;
}

/// A UTC DateTime here represents a calendar date, not the actual UTC instant
/// of local midnight. Actual query boundaries subtract the fixed day offset.
DateTime studyDate(DateTime utc, int offsetMinutes) {
  final local = utc.toUtc().add(Duration(minutes: offsetMinutes));
  return DateTime.utc(local.year, local.month, local.day);
}

class ReviewStatistics {
  const ReviewStatistics({
    this.reviewCount = 0,
    this.cardCount = 0,
    this.elapsed = Duration.zero,
    this.ratingCounts = const [0, 0, 0, 0],
  });
  final int reviewCount;
  final int cardCount;
  final Duration elapsed;
  final List<int> ratingCounts;
  double? get successRate => reviewCount == 0
      ? null
      : (reviewCount - ratingCounts.first) / reviewCount;
}

class TrendBucket {
  const TrendBucket({
    required this.start,
    required this.end,
    required this.reviewCount,
  });
  final DateTime start;
  final DateTime end; // Inclusive calendar date.
  final int reviewCount;
}

class StatisticsSnapshot {
  const StatisticsSnapshot({
    required this.today,
    required this.month,
    required this.offsetMinutes,
    required this.period,
    required this.rangeStart,
    required this.summary,
    required this.days,
    required this.trend,
    required this.streak,
    required this.activeDays,
  });
  final DateTime today;
  final DateTime month;
  final int offsetMinutes;
  final StatisticsPeriod period;
  final DateTime rangeStart;
  final ReviewStatistics summary;
  final Map<DateTime, ReviewStatistics> days; // Only selected calendar month.
  final List<TrendBucket> trend;
  final int streak;
  final int activeDays;
  DateTime get nextDayUtc => today
      .add(const Duration(days: 1))
      .subtract(Duration(minutes: offsetMinutes));
}
