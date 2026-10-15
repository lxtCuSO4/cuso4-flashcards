import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/daily_statistics.dart';

class StatisticsRepository {
  StatisticsRepository(
    this.db, {
    DateTime Function()? clock,
    Duration Function()? timezoneOffset,
  }) : _clock = clock ?? DateTime.now,
       _timezoneOffset =
           timezoneOffset ?? (() => DateTime.now().timeZoneOffset);

  final AppDatabase db;
  final DateTime Function() _clock;
  final Duration Function() _timezoneOffset;
  DateTime get nowUtc => _clock().toUtc();

  Stream<StatisticsSnapshot> watch({
    StatisticsPeriod period = StatisticsPeriod.week,
    DateTime? month,
  }) => db
      .customSelect('SELECT 1', readsFrom: {db.reviewLogs, db.appSettings})
      .watch()
      .asyncMap((_) => load(period: period, month: month));

  Future<StatisticsSnapshot> load({
    StatisticsPeriod period = StatisticsPeriod.week,
    DateTime? month,
  }) => db.transaction(() async {
    final offset = await _offsetMinutes();
    final today = studyDate(nowUtc, offset);
    final calendar = month == null
        ? DateTime.utc(today.year, today.month)
        : DateTime.utc(month.year, month.month);
    final end = today.add(const Duration(days: 1));
    final endUtc = end
        .subtract(Duration(minutes: offset))
        .millisecondsSinceEpoch;
    // Only grouped dates are read, never all source log rows. This query also
    // provides history-wide streak dates independently of the selected range.
    final activeRows = await db
        .customSelect(
          '''SELECT date(reviewed_at_utc / 1000.0, 'unixepoch', ? || ' minutes') AS day
      FROM review_logs WHERE reviewed_at_utc < ? GROUP BY day ORDER BY day DESC''',
          variables: [Variable(offset), Variable(endUtc)],
          readsFrom: {db.reviewLogs},
        )
        .get();
    final active = activeRows
        .map((r) => DateTime.parse('${r.read<String>('day')}T00:00:00Z'))
        .toSet();
    final rangeStart = period.days == null
        ? (active.isEmpty ? today : active.last)
        : today.subtract(Duration(days: period.days! - 1));
    final startUtc = rangeStart
        .subtract(Duration(minutes: offset))
        .millisecondsSinceEpoch;
    final summary = _totals(
      await db
          .customSelect(
            'SELECT $_aggregates FROM review_logs WHERE reviewed_at_utc >= ? AND reviewed_at_utc < ?',
            variables: [Variable(startUtc), Variable(endUtc)],
            readsFrom: {db.reviewLogs},
          )
          .getSingle(),
    );
    final rangeDays = await _daily(rangeStart, end, offset);
    final calendarEnd = DateTime.utc(calendar.year, calendar.month + 1);
    final days = calendar == rangeStart && calendarEnd == end
        ? rangeDays
        : await _daily(
            calendar,
            calendarEnd.isBefore(end) ? calendarEnd : end,
            offset,
          );
    var cursor = active.contains(today)
        ? today
        : today.subtract(const Duration(days: 1));
    var streak = 0;
    while (active.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return StatisticsSnapshot(
      today: today,
      month: calendar,
      offsetMinutes: offset,
      period: period,
      rangeStart: rangeStart,
      summary: summary,
      days: Map.unmodifiable(days),
      trend: _trend(rangeStart, today, rangeDays),
      streak: streak,
      activeDays: rangeDays.length,
    );
  });

  static const _aggregates =
      '''COUNT(*) AS reviews, COUNT(DISTINCT card_id) AS cards,
    COALESCE(SUM(elapsed_milliseconds), 0) AS elapsed,
    COUNT(CASE WHEN rating = 1 THEN 1 END) AS again,
    COUNT(CASE WHEN rating = 2 THEN 1 END) AS hard,
    COUNT(CASE WHEN rating = 3 THEN 1 END) AS good,
    COUNT(CASE WHEN rating = 4 THEN 1 END) AS easy''';

  ReviewStatistics _totals(QueryRow row) => ReviewStatistics(
    reviewCount: row.read<int>('reviews'),
    cardCount: row.read<int>('cards'),
    elapsed: Duration(milliseconds: row.read<int>('elapsed')),
    ratingCounts: List.unmodifiable([
      row.read<int>('again'),
      row.read<int>('hard'),
      row.read<int>('good'),
      row.read<int>('easy'),
    ]),
  );

  Future<Map<DateTime, ReviewStatistics>> _daily(
    DateTime start,
    DateTime end,
    int offset,
  ) async {
    if (!end.isAfter(start)) return {};
    final rows = await db
        .customSelect(
          '''SELECT date(reviewed_at_utc / 1000.0, 'unixepoch', ? || ' minutes') AS day,
      $_aggregates FROM review_logs WHERE reviewed_at_utc >= ? AND reviewed_at_utc < ?
      GROUP BY day ORDER BY day''',
          variables: [
            Variable(offset),
            Variable(
              start.subtract(Duration(minutes: offset)).millisecondsSinceEpoch,
            ),
            Variable(
              end.subtract(Duration(minutes: offset)).millisecondsSinceEpoch,
            ),
          ],
          readsFrom: {db.reviewLogs},
        )
        .get();
    return {
      for (final row in rows)
        DateTime.parse('${row.read<String>('day')}T00:00:00Z'): _totals(row),
    };
  }

  List<TrendBucket> _trend(
    DateTime start,
    DateTime today,
    Map<DateTime, ReviewStatistics> days,
  ) {
    final count = today.difference(start).inDays + 1;
    final step = math.max(1, (count / 12).ceil());
    final buckets = List.filled((count / step).ceil(), 0);
    for (final day in days.entries) {
      buckets[day.key.difference(start).inDays ~/ step] +=
          day.value.reviewCount;
    }
    return List.unmodifiable(
      List.generate(buckets.length, (index) {
        final from = start.add(Duration(days: step * index));
        final to = from.add(Duration(days: step - 1));
        return TrendBucket(
          start: from,
          end: to.isAfter(today) ? today : to,
          reviewCount: buckets[index],
        );
      }),
    );
  }

  Future<int> _offsetMinutes() async {
    final row = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals('studyDayOffsetMinutes'))).getSingleOrNull();
    Object? value;
    try {
      value = row == null
          ? _timezoneOffset().inMinutes
          : jsonDecode(row.valueJson);
    } on FormatException {
      throw StateError('学习日设置无效，请保留数据并恢复有效备份。');
    }
    if (value is! int || value < -840 || value > 840) {
      throw StateError('学习日设置无效，请保留数据并恢复有效备份。');
    }
    return value;
  }
}
