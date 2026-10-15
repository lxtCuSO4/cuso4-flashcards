import 'dart:convert';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/records/data/statistics_repository.dart';
import 'package:cuso4_flashcards/features/records/domain/daily_statistics.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:cuso4_flashcards/features/study/domain/scheduler.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late StatisticsRepository repository;
  late DateTime now;
  late Duration offset;
  late int cardId;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 15, 8);
    offset = const Duration(hours: 8);
    repository = StatisticsRepository(
      db,
      clock: () => now,
      timezoneOffset: () => offset,
    );
    final deck = await DeckRepository(db).createDeck('操作系统');
    await NoteRepository(db)
        .createBasicNote(deckId: deck, front: '进程', back: '运行中的程序');
    cardId = (await db.select(db.cards).get()).single.id;
  });
  tearDown(() => db.close());
  Future<void> log(DateTime at, int rating, {int milliseconds = 1000}) async {
    await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            cardId: cardId,
            reviewedAtUtc: at.millisecondsSinceEpoch,
            rating: rating,
            elapsedMilliseconds: milliseconds,
            beforeStateJson: jsonEncode({'state': 0}),
            afterStateJson: '{}',
          ),
        );
  }

  test(
    'empty data has no fabricated rate or writes and includes zero days',
    () async {
      final snapshot = await repository.load(period: StatisticsPeriod.week);
      expect(snapshot.summary.reviewCount, 0);
      expect(snapshot.summary.cardCount, 0);
      expect(snapshot.summary.successRate, isNull);
      expect(snapshot.streak, 0);
      expect(snapshot.trend.length, 7);
      expect(snapshot.trend.every((d) => d.reviewCount == 0), isTrue);
      expect(snapshot.month, DateTime.utc(2026, 10));
      expect(await db.select(db.appSettings).get(), isEmpty);
    },
  );

  test(
    'counts ratings separately from unique cards and sums recorded duration',
    () async {
      for (var rating = 1; rating <= 4; rating++) {
        await log(now, rating, milliseconds: rating * 1000);
      }
      final snapshot = await repository.load();
      expect(snapshot.summary.reviewCount, 4);
      expect(snapshot.summary.cardCount, 1);
      expect(snapshot.summary.elapsed, const Duration(seconds: 10));
      expect(snapshot.summary.successRate, .75);
      expect(snapshot.summary.ratingCounts, [1, 1, 1, 1]);
      expect(snapshot.days[DateTime.utc(2026, 10, 15)]!.reviewCount, 4);
      expect(snapshot.activeDays, 1);
      expect(snapshot.streak, 1);
    },
  );

  test(
    'pinned timezone uses inclusive midnight and excludes following midnight',
    () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'studyDayOffsetMinutes',
              valueJson: '480',
            ),
          );
      await log(DateTime.utc(2026, 10, 14, 15, 59), 1);
      await log(DateTime.utc(2026, 10, 14, 16), 3);
      await log(DateTime.utc(2026, 10, 15, 16), 4);
      offset = const Duration(hours: -8);
      final snapshot = await repository.load();
      expect(snapshot.today, DateTime.utc(2026, 10, 15));
      expect(snapshot.days[DateTime.utc(2026, 10, 14)]!.reviewCount, 1);
      expect(snapshot.days[DateTime.utc(2026, 10, 15)]!.reviewCount, 1);
      expect(snapshot.days.containsKey(DateTime.utc(2026, 10, 16)), isFalse);
      expect(snapshot.summary.reviewCount, 2);
      expect(snapshot.streak, 2);
      expect(snapshot.offsetMinutes, 480);
    },
  );

  test(
    'fallback timezone can cross year boundary without writing a preference',
    () async {
      now = DateTime.utc(2027, 1, 1, 1);
      offset = const Duration(hours: -5);
      await log(DateTime.utc(2026, 12, 31, 4, 59), 2);
      await log(DateTime.utc(2026, 12, 31, 5), 3);
      final snapshot = await repository.load();
      expect(snapshot.today, DateTime.utc(2026, 12, 31));
      expect(snapshot.days[DateTime.utc(2026, 12, 30)]!.reviewCount, 1);
      expect(snapshot.days[DateTime.utc(2026, 12, 31)]!.reviewCount, 1);
      expect(await db.select(db.appSettings).get(), isEmpty);
    },
  );

  test('7, 30, 90 and all ranges deduplicate cards across days; month is independent', () async {
    for (final days in [0, 6, 7, 29, 30, 89, 90]) {
      await log(now.subtract(Duration(days: days)), 3);
    }
    for (final entry in {
      StatisticsPeriod.week: 2,
      StatisticsPeriod.month: 4,
      StatisticsPeriod.quarter: 6,
      StatisticsPeriod.all: 7,
    }.entries) {
      final snapshot = await repository.load(
        period: entry.key,
        month: DateTime.utc(2026, 8),
      );
      expect(snapshot.summary.reviewCount, entry.value);
      expect(snapshot.summary.cardCount, 1);
      expect(
        snapshot.trend.fold<int>(0, (sum, b) => sum + b.reviewCount),
        entry.value,
      );
      expect(snapshot.trend.length, lessThanOrEqualTo(12));
      expect(snapshot.month, DateTime.utc(2026, 8));
    }
  });

  test(
    'streak includes yesterday when today is empty and stops at gaps',
    () async {
      for (final days in [1, 2, 3, 5]) {
        await log(now.subtract(Duration(days: days)), 3);
      }
      expect((await repository.load()).streak, 3);
      now = now.add(const Duration(days: 1));
      expect((await repository.load()).streak, 0);
      now = now.subtract(const Duration(days: 1));
      await log(now, 3);
      expect((await repository.load()).streak, 4);
    },
  );

  test('watch updates after actual rating and undo without changing schedule itself', () async {
    final study = StudyRepository(
      db,
      clock: () => now,
      timezoneOffset: () => offset,
    );
    await db
        .update(db.cards)
        .write(CardsCompanion(dueAtUtc: Value(now.millisecondsSinceEpoch)));
    final before = await study.getCard(cardId);
    final values = <int>[];
    final subscription = repository.watch().listen(
      (s) => values.add(s.summary.reviewCount),
    );
    addTearDown(subscription.cancel);
    Future<void> waitFor(int value) async {
      for (
        var i = 0;
        i < 100 && (values.isEmpty || values.last != value);
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(values.last, value);
    }

    await waitFor(0);
    final receipt = await study.rateCard(
      before,
      ReviewRating.good,
      elapsed: const Duration(seconds: 12),
    );
    await waitFor(1);
    expect((await repository.load()).summary.elapsed.inSeconds, 12);
    expect((await study.getCard(cardId)).toJson(), receipt.after.toJson());
    await study.undoReview(receipt.logId);
    await waitFor(0);
    expect((await study.getCard(cardId)).toJson(), before.toJson());
    expect((await repository.load()).summary.successRate, isNull);
    await subscription.cancel();
  });

  test(
    'invalid pinned day setting is reported instead of regrouping history',
    () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'studyDayOffsetMinutes',
              valueJson: 'invalid',
            ),
          );
      await expectLater(repository.load(), throwsStateError);
    },
  );

  test('month-end and leap day keep earlier calendar days outside a seven-day range', () async {
    now = DateTime.utc(2028, 2, 29, 8);
    await log(DateTime.utc(2028, 2, 1, 8), 3);
    await log(now, 4);
    final snapshot = await repository.load();
    expect(snapshot.summary.reviewCount, 1);
    expect(snapshot.days.length, 2);
    expect(snapshot.days[DateTime.utc(2028, 2, 1)]!.reviewCount, 1);
    expect(snapshot.days[DateTime.utc(2028, 2, 29)]!.reviewCount, 1);
    expect(snapshot.trend.length, 7);
  });
}
