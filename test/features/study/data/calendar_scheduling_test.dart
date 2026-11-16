import 'dart:convert';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/settings/domain/study_settings.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:cuso4_flashcards/features/study/data/calendar_scheduler.dart';
import 'package:cuso4_flashcards/features/study/application/study_session_controller.dart';
import 'package:cuso4_flashcards/features/decks/domain/flashcard.dart';
import 'package:cuso4_flashcards/features/study/domain/scheduler.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final json = <String, dynamic>{
    'dailyNewLimit': 20,
    'dailyReviewLimit': 200,
    'desiredRetentionPercent': 90,
    'schedulingMode': 'calendar',
    'againMinutes': 10,
    'hardDays': 1,
    'goodDays': 3,
    'easyDays': 7,
  };
  late AppDatabase db;
  late DateTime now;
  late StudyRepository repository;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 11, 16, 12);
    final deck = await DeckRepository(db).createDeck('按天排程');
    await NoteRepository(db).createBasicNote(deckId: deck, front: '问题');
    await db.customStatement('UPDATE cards SET due_at_utc = ?', [
      now.millisecondsSinceEpoch,
    ]);
    repository = StudyRepository(
      db,
      clock: () => now,
      timezoneOffset: () => const Duration(hours: 8),
    ).withSettings(StudySettings.fromJson(json));
  });
  tearDown(() => db.close());

  test('custom settings round trip and reject unknown or unordered rules', () {
    expect(StudySettings.fromJson(json).toJson(), json);
    for (final overrides in [
      {'schedulingMode': 'unknown'},
      {'againMinutes': 0},
      {'hardDays': 0},
      {'goodDays': 1},
      {'easyDays': 2},
      {'goodDays': '3'},
    ]) {
      expect(
        () => StudySettings.fromJson({...json, ...overrides}),
        throwsArgumentError,
      );
    }
  });

  test(
    '10 minutes and natural-day 1/3/7 intervals match persisted dates and undo',
    () async {
      final initial = (await repository.loadQueue()).single;
      final expected = {
        ReviewRating.again: DateTime.utc(2026, 11, 16, 12, 10),
        ReviewRating.hard: DateTime.utc(2026, 11, 16, 16),
        ReviewRating.good: DateTime.utc(2026, 11, 18, 16),
        ReviewRating.easy: DateTime.utc(2026, 11, 22, 16),
      };
      final preview = repository.scheduler.previewIntervals(
        initial,
        reviewedAtUtc: now,
      );
      for (final rating in ReviewRating.values) {
        expect(now.add(preview[rating]!), expected[rating]);
        final receipt = await repository.rateCard(initial, rating);
        expect(receipt.after.dueAtUtc, expected[rating]);
        final row = (await db.select(db.reviewLogs).get()).single;
        expect(
          (jsonDecode(row.afterStateJson) as Map)['schedulingMode'],
          'calendar',
        );
        await repository.undoReview(receipt.logId);
        expect(
          (await repository.getCard(initial.id)).toJson(),
          initial.toJson(),
        );
      }
    },
  );

  test('legacy settings default to unchanged FSRS and switching does not rewrite cards', () async {
    final initial = (await repository.loadQueue()).single;
    final fsrs = repository.withSettings(
      StudySettings.fromJson({
        'dailyNewLimit': 20,
        'dailyReviewLimit': 200,
        'desiredRetentionPercent': 90,
      }),
    );
    expect(
      fsrs.scheduler.previewIntervals(
        initial,
        reviewedAtUtc: now,
      )[ReviewRating.again],
      const Duration(minutes: 1),
    );
    expect((await repository.getCard(initial.id)).toJson(), initial.toJson());
    final receipt = await repository.rateCard(initial, ReviewRating.good);
    now = receipt.after.dueAtUtc;
    final switched = await fsrs.rateCard(receipt.after, ReviewRating.good);
    expect(switched.after.stability, greaterThan(0));
  });

  test(
    'calendar boundaries, pinned timezone and review state remain consistent',
    () async {
      final card = (await repository.loadQueue()).single; // Pins UTC+8.
      final changedDeviceZone = StudyRepository(
        db,
        clock: () => now,
        timezoneOffset: () => const Duration(hours: -5),
      ).withSettings(StudySettings.fromJson(json));
      await changedDeviceZone.loadQueue();
      expect(
        changedDeviceZone.scheduler.previewIntervals(
          card,
          reviewedAtUtc: now,
        )[ReviewRating.hard],
        const Duration(hours: 4),
      );
      final calendar = repository.scheduler as CalendarScheduler;
      for (final entry in [
        (DateTime.utc(2027, 12, 31, 15, 59), DateTime.utc(2027, 12, 31, 16)),
        (DateTime.utc(2028, 2, 28, 15, 59), DateTime.utc(2028, 2, 28, 16)),
        (DateTime.utc(2028, 2, 29, 15, 59), DateTime.utc(2028, 2, 29, 16)),
      ]) {
        expect(calendar.dueFor(ReviewRating.hard, entry.$1), entry.$2);
      }
      await repository.setFavorite(card.id, true);
      final receipt = await repository.rateCard(
        await repository.getCard(card.id),
        ReviewRating.good,
      );
      expect(receipt.after.state, CardState.review);
      expect(receipt.after.isFavorite, isTrue);
      now = receipt.after.dueAtUtc;
      expect(
        await repository
            .withSettings(
              StudySettings.fromJson({...json, 'dailyReviewLimit': 0}),
            )
            .loadQueue(),
        isEmpty,
      );
    },
  );

  test(
    'transaction rejects a preview from the previous calendar day',
    () async {
      final card = (await repository.loadQueue()).single;
      final day = (repository.scheduler as CalendarScheduler).dayAt(now);
      now = DateTime.utc(2026, 11, 16, 16, 1);
      await expectLater(
        repository.rateCard(card, ReviewRating.good, expectedCalendarDay: day),
        throwsStateError,
      );
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      expect((await repository.getCard(card.id)).toJson(), card.toJson());
    },
  );

  test(
    'crossing midnight refreshes displayed targets before allowing a rating',
    () async {
      now = DateTime.utc(2026, 11, 16, 15, 59);
      final session = StudySessionController(repository);
      addTearDown(session.dispose);
      await session.start();
      session.showAnswer();
      expect(session.previewLabels[ReviewRating.hard], '明天 · 11/17');
      now = DateTime.utc(2026, 11, 16, 16, 1);
      await session.rate(ReviewRating.hard);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      expect(session.error, contains('跨过午夜'));
      expect(session.previewLabels[ReviewRating.hard], '明天 · 11/18');
      await session.rate(ReviewRating.hard);
      expect((await db.select(db.reviewLogs).get()).single.rating, 2);
      expect(session.completedReviews, 1);
    },
  );
}
