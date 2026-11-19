import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/daily_statistics.dart';
import 'statistics_repository.dart';

class PracticeDay {
  const PracticeDay({this.answered = 0, this.correct = 0, this.elapsedMs = 0});
  final int answered, correct, elapsedMs;
  int get wrong => answered - correct;
  double? get accuracy => answered == 0 ? null : correct / answered;
  PracticeDay operator +(PracticeDay other) => PracticeDay(
    answered: answered + other.answered,
    correct: correct + other.correct,
    elapsedMs: elapsedMs + other.elapsedMs,
  );
}

class PracticeStatisticsSnapshot {
  const PracticeStatisticsSnapshot({
    required this.today,
    required this.month,
    required this.offset,
    required this.start,
    required this.period,
    required this.days,
    required this.summary,
  });
  final DateTime today, month, start;
  final int offset;
  final StatisticsPeriod period;
  final Map<DateTime, PracticeDay> days;
  final PracticeDay summary;

  // Calendar presentation only: practice totals remain separate from ratings.
  StatisticsSnapshot get calendar => StatisticsSnapshot(
    today: today,
    month: month,
    offsetMinutes: offset,
    period: period,
    rangeStart: start,
    summary: const ReviewStatistics(),
    days: {
      for (final entry in days.entries)
        entry.key: ReviewStatistics(
          reviewCount: entry.value.answered,
          elapsed: Duration(milliseconds: entry.value.elapsedMs),
        ),
    },
    trend: const [],
    streak: 0,
    activeDays: days.length,
  );
}

class PracticeStatisticsRepository {
  PracticeStatisticsRepository(this.db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final AppDatabase db;
  final DateTime Function() _clock;

  Stream<PracticeStatisticsSnapshot> watch({
    StatisticsPeriod period = StatisticsPeriod.week,
    DateTime? month,
  }) => db
      .customSelect('SELECT 1', readsFrom: {db.appSettings})
      .watch()
      .asyncMap((_) => load(period: period, month: month));

  Future<PracticeStatisticsSnapshot> load({
    StatisticsPeriod period = StatisticsPeriod.week,
    DateTime? month,
  }) => db.transaction(() async {
    final offset = await StatisticsRepository(db).readOffsetMinutes();
    final today = studyDate(_clock().toUtc(), offset);
    final calendar = month == null
        ? DateTime.utc(today.year, today.month)
        : DateTime.utc(month.year, month.month);
    final start = period.days == null
        ? DateTime.utc(1970)
        : today.subtract(Duration(days: period.days! - 1));
    final first = calendar.isBefore(start) ? calendar : start;
    final end = today.add(const Duration(days: 1));
    final fromUtc = first.subtract(Duration(minutes: offset));
    final toUtc = end.subtract(Duration(minutes: offset));
    final rows = await db
        .customSelect(
          '''
      WITH events AS (
        SELECT json_extract(value_json, '\$.submittedAtUtc') AS submitted,
          json_extract(value_json, '\$.correct') AS correct,
          json_extract(value_json, '\$.elapsedMs') AS elapsed
        FROM app_settings WHERE key >= ? AND key < ? AND json_valid(value_json)
      )
      SELECT date(submitted / 1000.0, 'unixepoch', ? || ' minutes') AS day,
        COUNT(*) AS answered, SUM(CASE WHEN correct = 1 THEN 1 ELSE 0 END) AS correct,
        SUM(CASE WHEN elapsed >= 0 THEN elapsed ELSE 0 END) AS elapsed
      FROM events WHERE submitted >= ? AND submitted < ? GROUP BY day ORDER BY day
    ''',
          variables: [
            Variable('practice:attempt:${_date(fromUtc)}'),
            Variable(
              'practice:attempt:${_date(toUtc.add(const Duration(days: 1)))}',
            ),
            Variable(offset),
            Variable(fromUtc.millisecondsSinceEpoch),
            Variable(toUtc.millisecondsSinceEpoch),
          ],
          readsFrom: {db.appSettings},
        )
        .get();
    final days = {
      for (final row in rows)
        DateTime.parse('${row.read<String>('day')}T00:00:00Z'): PracticeDay(
          answered: row.read<int>('answered'),
          correct: row.read<int>('correct'),
          elapsedMs: row.read<int>('elapsed'),
        ),
    };
    var summary = const PracticeDay();
    for (final entry in days.entries) {
      if (!entry.key.isBefore(start)) summary += entry.value;
    }
    return PracticeStatisticsSnapshot(
      today: today,
      month: calendar,
      offset: offset,
      start: start,
      period: period,
      days: Map.unmodifiable(days),
      summary: summary,
    );
  });

  Future<List<Map<String, dynamic>>> dayDetails(
    DateTime date,
    int offset,
  ) async {
    final from = date.subtract(Duration(minutes: offset));
    final to = date
        .add(const Duration(days: 1))
        .subtract(Duration(minutes: offset));
    final rows = await db
        .customSelect(
          '''SELECT value_json FROM app_settings
      WHERE key >= ? AND key < ? AND json_valid(value_json)
      AND json_extract(value_json, '\$.submittedAtUtc') >= ?
      AND json_extract(value_json, '\$.submittedAtUtc') < ?
      ORDER BY json_extract(value_json, '\$.submittedAtUtc') DESC''',
          variables: [
            Variable('practice:attempt:${_date(from)}'),
            Variable(
              'practice:attempt:${_date(to.add(const Duration(days: 1)))}',
            ),
            Variable(from.millisecondsSinceEpoch),
            Variable(to.millisecondsSinceEpoch),
          ],
          readsFrom: {db.appSettings},
        )
        .get();
    return rows
        .map(
          (row) => Map<String, dynamic>.from(
            jsonDecode(row.read<String>('value_json')) as Map,
          ),
        )
        .toList();
  }

  String _date(DateTime value) =>
      value.toUtc().toIso8601String().substring(0, 10);
}
