import 'dart:async';
import 'dart:convert';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/flashcard.dart';
import 'package:cuso4_flashcards/features/home/application/home_summary_service.dart';
import 'package:cuso4_flashcards/features/settings/data/study_settings_repository.dart';
import 'package:cuso4_flashcards/features/settings/domain/study_settings.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:cuso4_flashcards/features/study/domain/scheduler.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late StudyRepository study;
  late HomeSummaryService service;
  late DateTime now;
  late Duration offset;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 15, 8);
    offset = const Duration(hours: 8);
    study = StudyRepository(db, clock: () => now, timezoneOffset: () => offset);
    service = HomeSummaryService(db, study: study);
  });
  tearDown(() => db.close());

  Future<Flashcard> card(
    int deck, {
    CardState state = CardState.newCard,
    DateTime? due,
  }) async {
    final note = await NoteRepository(db)
        .createBasicNote(deckId: deck, front: 'CuSO₄', back: '硫酸铜');
    final row = await (db.select(
      db.cards,
    )..where((c) => c.noteId.equals(note))).getSingle();
    await (db.update(db.cards)..where((c) => c.id.equals(row.id))).write(
      CardsCompanion(
        state: Value(state.index),
        dueAtUtc: Value((due ?? now).millisecondsSinceEpoch),
        stability: Value(state == CardState.newCard ? null : 12.0),
        difficulty: Value(state == CardState.newCard ? null : 5.0),
        lastReviewAtUtc: Value(
          state == CardState.newCard
              ? null
              : now.subtract(const Duration(days: 10)).millisecondsSinceEpoch,
        ),
      ),
    );
    return study.getCard(row.id);
  }

  Future<void> log(Flashcard card, DateTime at) => db
      .into(db.reviewLogs)
      .insert(
        ReviewLogsCompanion.insert(
          cardId: card.id,
          reviewedAtUtc: at.millisecondsSinceEpoch,
          rating: 3,
          elapsedMilliseconds: 1000,
          beforeStateJson: jsonEncode({...card.toJson(), 'state': 2}),
          afterStateJson: '{}',
        ),
      );

  test(
    'empty overview is read-only and does not pin timezone or settings',
    () async {
      final summary = await service.load();
      expect(summary.availability.availableCards, 0);
      expect(summary.availability.totalCards, 0);
      expect(summary.availability.today, DateTime.utc(2026, 10, 15));
      expect(summary.availability.nextDueAtUtc, isNull);
      expect(summary.studiedCards, 0);
      expect(summary.ratingCount, 0);
      expect(summary.streak, 0);
      expect(summary.deckCount, 0);
      expect(summary.decks, isEmpty);
      expect(await db.select(db.appSettings).get(), isEmpty);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
    },
  );

  test(
    'availability shares per-deck limits with queue, including child decks',
    () async {
      final decks = DeckRepository(db);
      final root = await decks.createDeck('A');
      final child = await decks.createDeck('chapter', parentId: root);
      final other = await decks.createDeck('B');
      await StudySettingsRepository(db)
          .save(StudySettings(dailyNewLimit: 1, dailyReviewLimit: 1));
      for (final deck in [root, child, other]) {
        for (var i = 0; i < 3; i++) {
          await card(deck);
          await card(deck, state: CardState.review);
        }
      }
      await card(child, state: CardState.learning);
      await card(child, state: CardState.relearning);
      await card(
        root,
        state: CardState.review,
        due: now.add(const Duration(days: 2)),
      );
      final settings = await StudySettingsRepository(db).load();
      final queue = await study.withSettings(settings).loadQueue(limit: 500);
      final summary = await service.load();
      final availability = summary.availability;
      expect(availability.availableCards, queue.length);
      expect(availability.newCards, 3);
      expect(availability.reviews, 3);
      expect(availability.learning, 2);
      expect(availability.blockedNewCards, 6);
      expect(availability.blockedReviews, 6);
      expect(availability.totalCards, 21);
      expect(summary.deckCount, 3);
      expect(summary.decks.map((d) => d.name), ['A', 'B']);
      expect(summary.decks.first.cardCount, 15);
      expect(summary.decks.last.cardCount, 6);
    },
  );

  test('summary is not truncated by the 50-card queue batch', () async {
    final deck = await DeckRepository(db).createDeck('large');
    await StudySettingsRepository(db).save(StudySettings(dailyNewLimit: 99));
    for (var i = 0; i < 63; i++) {
      await card(deck);
    }
    expect(
      (await study.withSettings(StudySettings(dailyNewLimit: 99)).loadQueue())
          .length,
      50,
    );
    expect((await service.load()).availability.newCards, 63);
  });

  test(
    'ratings and undo stream update unique learned cards, streak and quota',
    () async {
      final deck = await DeckRepository(db).createDeck('A');
      final first = await card(deck);
      await card(deck);
      final past = await card(deck, due: now.add(const Duration(days: 10)));
      await log(past, now.subtract(const Duration(days: 1)));
      await StudySettingsRepository(db).save(StudySettings(dailyNewLimit: 1));
      final stream = StreamIterator(service.watch());
      addTearDown(stream.cancel);
      expect(await stream.moveNext(), isTrue);
      expect(stream.current.streak, 1);
      expect(stream.current.availability.newCards, 1);
      final configured = study.withSettings(StudySettings(dailyNewLimit: 1));
      await configured.rateCard(first, ReviewRating.again);
      while (await stream.moveNext()) {
        if (stream.current.ratingCount == 1) break;
      }
      expect(stream.current.studiedCards, 1);
      expect(stream.current.streak, 2);
      expect(stream.current.availability.newCards, 0);
      now = now.add(const Duration(minutes: 1));
      final learning = await configured.getCard(first.id);
      final second = await configured.rateCard(learning, ReviewRating.good);
      while (await stream.moveNext()) {
        if (stream.current.ratingCount == 2) break;
      }
      expect(stream.current.studiedCards, 1);
      expect(stream.current.availability.blockedNewCards, 1);
      await configured.undoReview(second.logId);
      while (await stream.moveNext()) {
        if (stream.current.ratingCount == 1) break;
      }
      expect(stream.current.studiedCards, 1);
      expect(stream.current.availability.learning, 1);
      await StudySettingsRepository(db).save(StudySettings(dailyNewLimit: 2));
      while (await stream.moveNext()) {
        if (stream.current.availability.newCards == 1) break;
      }
      expect(stream.current.availability.availableCards, 2);
    },
  );

  test(
    'fixed day boundaries ignore travel timezone and reset at midnight',
    () async {
      final deck = await DeckRepository(db).createDeck('A');
      final c = await card(deck);
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'studyDayOffsetMinutes',
              valueJson: '480',
            ),
          );
      now = DateTime.utc(2026, 10, 15, 15, 59, 59);
      await log(c, DateTime.utc(2026, 10, 14, 15, 59, 59));
      await log(c, DateTime.utc(2026, 10, 14, 16));
      await log(c, DateTime.utc(2026, 10, 15, 16));
      offset = const Duration(hours: -8);
      var summary = await service.load();
      expect(summary.availability.today, DateTime.utc(2026, 10, 15));
      expect(summary.ratingCount, 1);
      expect(summary.streak, 2);
      expect(summary.availability.dayEndUtc, DateTime.utc(2026, 10, 15, 16));
      now = DateTime.utc(2026, 10, 15, 16);
      summary = await service.load();
      expect(summary.availability.today, DateTime.utc(2026, 10, 16));
      expect(summary.ratingCount, 1);
      expect(summary.streak, 3);
    },
  );

  test(
    'next due ignores quota-blocked future cards and includes learning',
    () async {
      final deck = await DeckRepository(db).createDeck('A');
      await StudySettingsRepository(db).save(StudySettings(dailyNewLimit: 0));
      await card(deck, due: now.add(const Duration(minutes: 1)));
      await card(
        deck,
        state: CardState.review,
        due: now.add(const Duration(minutes: 3)),
      );
      await card(
        deck,
        state: CardState.learning,
        due: now.add(const Duration(minutes: 5)),
      );
      var summary = await service.load();
      expect(summary.availability.availableCards, 0);
      expect(
        summary.availability.nextDueAtUtc,
        now.add(const Duration(minutes: 3)),
      );
      await StudySettingsRepository(db)
          .save(StudySettings(dailyNewLimit: 0, dailyReviewLimit: 0));
      summary = await service.load();
      expect(
        summary.availability.nextDueAtUtc,
        now.add(const Duration(minutes: 5)),
      );
      now = now.add(const Duration(minutes: 5));
      summary = await service.load();
      expect(summary.availability.learning, 1);
      expect(summary.availability.blockedNewCards, 1);
      expect(summary.availability.blockedReviews, 1);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      expect(
        (await db.select(db.appSettings).get()).any(
          (s) => s.key == 'studyDayOffsetMinutes',
        ),
        isFalse,
      );
    },
  );

  test(
    'corrupt settings or fixed timezone produce errors rather than defaults',
    () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: StudySettingsRepository.settingKey,
              valueJson: '{',
            ),
          );
      await expectLater(service.load(), throwsStateError);
      await StudySettingsRepository(db).save(StudySettings());
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'studyDayOffsetMinutes',
              valueJson: '9999',
            ),
          );
      await expectLater(service.load(), throwsStateError);
    },
  );

  test('deck preview stays bounded and reacts to cascade deletion', () async {
    final decks = DeckRepository(db);
    for (var i = 0; i < 7; i++) {
      final id = await decks.createDeck('deck$i');
      await card(id);
    }
    var summary = await service.load();
    expect(summary.deckCount, 7);
    expect(summary.decks.length, 5);
    await decks.deleteDeck(summary.decks.first.id);
    summary = await service.load();
    expect(summary.deckCount, 6);
    expect(summary.availability.totalCards, 6);
    expect(summary.decks.first.name, 'deck1');
  });
}
