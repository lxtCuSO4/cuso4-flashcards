import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/study/application/study_session_controller.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:cuso4_flashcards/features/study/domain/scheduler.dart';
import 'package:cuso4_flashcards/features/study/data/fsrs_scheduler.dart';
import 'package:cuso4_flashcards/features/settings/data/study_settings_repository.dart';
import 'package:cuso4_flashcards/features/settings/domain/study_settings.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late StudyRepository repository;
  late StudySessionController session;
  late int deck;
  late DateTime now;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 15, 8);
    deck = await DeckRepository(db).createDeck('chemistry');
    final notes = NoteRepository(db);
    await notes.createBasicNote(deckId: deck, front: 'CuSO4', back: '硫酸铜');
    await notes.createClozeNote(deckId: deck, text: '硫酸铜晶体呈 {{c1::蓝色}}');
    await db
        .update(db.cards)
        .write(CardsCompanion(dueAtUtc: Value(now.millisecondsSinceEpoch)));
    repository = StudyRepository(
      db,
      clock: () => now,
      timezoneOffset: () => const Duration(hours: 8),
    );
    session = StudySessionController(repository, deckId: deck);
  });
  tearDown(() async {
    session.dispose();
    await db.close();
  });

  test(
    'answer gating and an async rating lock prevent duplicate submission',
    () async {
      await session.start();
      expect(session.current!.note.fields['front'], 'CuSO4');
      expect(session.answerVisible, isFalse);
      expect(session.previewIntervals, isEmpty);
      await session.rate(ReviewRating.easy);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      final before = session.current!.card.toJson();
      session.showAnswer();
      expect(session.previewIntervals.length, 4);
      expect(session.current!.card.toJson(), before);
      final rating = session.rate(ReviewRating.easy);
      await session.rate(ReviewRating.easy);
      await rating;
      expect((await db.select(db.reviewLogs).get()).length, 1);
      expect(session.completedReviews, 1);
      expect(session.current!.note.fields['text'], contains('{{c1::蓝色}}'));
      expect(session.answerVisible, isFalse);
      expect(session.canUndo, isTrue);
    },
  );

  test('undo restores the exact prior card and favorite does not change its schedule', () async {
    await session.start();
    final card = session.current!.card;
    session.showAnswer();
    await session.rate(ReviewRating.good);
    await session.undo();
    expect(session.current!.card.toJson(), card.toJson());
    expect(session.completedReviews, 0);
    expect(session.answerVisible, isFalse);
    expect(session.canUndo, isFalse);
    await session.toggleFavorite();
    expect(session.current!.card.isFavorite, isTrue);
    expect(session.current!.card.toJson(), card.toJson());
    expect(await db.select(db.reviewLogs).get(), isEmpty);
  });

  test('a failed grade retains the answer and card for a safe retry', () async {
    await session.start();
    final id = session.current!.card.id;
    await db.customStatement(
      "CREATE TRIGGER fail_review BEFORE INSERT ON review_logs BEGIN SELECT RAISE(FAIL, 'failure'); END",
    );
    session.showAnswer();
    await session.rate(ReviewRating.easy);
    expect(session.busy, isFalse);
    expect(session.error, isNotNull);
    expect(session.answerVisible, isTrue);
    expect(session.current!.card.id, id);
    expect(session.completedReviews, 0);
    await db.customStatement('DROP TRIGGER fail_review');
    await session.rate(ReviewRating.easy);
    expect(session.completedReviews, 1);
    expect(session.error, isNull);
  });

  test('completion means no currently eligible cards, not that future learning is erased', () async {
    await session.start();
    session.showAnswer();
    await session.rate(ReviewRating.good);
    session.showAnswer();
    await session.rate(ReviewRating.good);
    expect(session.isComplete, isTrue);
    expect(session.current, isNull);
    expect(session.completedReviews, 2);
    expect(
      (await db.select(db.cards).get()).every((c) => c.state == 1),
      isTrue,
    );
    now = now.add(const Duration(minutes: 10));
    await session.start();
    expect(session.isComplete, isFalse);
    expect(session.current, isNotNull);
  });

  test('saved limits apply before loading; undo and the next day restore allowance', () async {
    final settings = StudySettingsRepository(db);
    await settings.save(StudySettings(dailyNewLimit: 1));
    session.dispose();
    session = StudySessionController(
      repository,
      deckId: deck,
      loadSettings: settings.load,
    );
    await session.start();
    expect(session.repository.dailyNewLimit, 1);
    session.showAnswer();
    await session.rate(ReviewRating.easy);
    expect(session.isComplete, isTrue);
    await session.undo();
    expect(session.current, isNotNull);
    session.showAnswer();
    await session.rate(ReviewRating.easy);
    expect(session.isComplete, isTrue);
    now = now.add(const Duration(days: 1));
    await session.start();
    expect(session.current, isNotNull);
  });

  test('zero saved limits block new and review, while learning and relearning continue', () async {
    final settings = StudySettingsRepository(db);
    await settings.save(StudySettings(dailyNewLimit: 0, dailyReviewLimit: 0));
    session.dispose();
    session = StudySessionController(
      repository,
      deckId: deck,
      loadSettings: settings.load,
    );
    await session.start();
    expect(session.isComplete, isTrue);
    final cached = (await repository.loadQueue(deckId: deck)).first;
    await expectLater(
      session.repository.rateCard(cached, ReviewRating.good),
      throwsStateError,
    );
    await db.update(db.cards).write(const CardsCompanion(state: Value(2)));
    await session.start();
    expect(session.isComplete, isTrue);
    final review = await repository.getCard(cached.id);
    await expectLater(
      session.repository.rateCard(review, ReviewRating.good),
      throwsStateError,
    );
    await db.update(db.cards).write(const CardsCompanion(state: Value(1)));
    await session.start();
    expect(session.current, isNotNull);
    await db.update(db.cards).write(const CardsCompanion(state: Value(3)));
    await session.start();
    expect(session.current, isNotNull);
  });

  test('retention snapshot keeps preview and rating consistent without bulk rescheduling', () async {
    await db
        .update(db.cards)
        .write(
          CardsCompanion(
            state: const Value(2),
            stability: const Value(12),
            difficulty: const Value(5),
            repetitions: const Value(7),
            lastReviewAtUtc: Value(
              now.subtract(const Duration(days: 15)).millisecondsSinceEpoch,
            ),
          ),
        );
    final before = await db.select(db.cards).get();
    final settings = StudySettingsRepository(db);
    await settings.save(StudySettings(desiredRetentionPercent: 95));
    expect(
      (await db.select(db.cards).get()).map((c) => c.toJson()),
      before.map((c) => c.toJson()),
    );
    session.dispose();
    session = StudySessionController(
      repository,
      deckId: deck,
      loadSettings: settings.load,
    );
    await session.start();
    final card = session.current!.card;
    session.showAnswer();
    final preview = session.previewIntervals[ReviewRating.good]!;
    final defaultPreview = FsrsScheduler().previewIntervals(
      card,
      reviewedAtUtc: now,
    )[ReviewRating.good]!;
    expect(preview, lessThan(defaultPreview));
    await settings.save(StudySettings(desiredRetentionPercent: 80));
    await session.rate(ReviewRating.good);
    expect(
      (await repository.getCard(card.id)).dueAtUtc.difference(now),
      preview,
    );
    final next = StudySessionController(
      repository,
      deckId: deck,
      loadSettings: settings.load,
    );
    addTearDown(next.dispose);
    await next.start();
    expect(next.repository.scheduler.desiredRetention, .8);
    expect(session.repository.scheduler.desiredRetention, .95);
  });

  test(
    'settings load failure blocks default fallback and can safely retry',
    () async {
      var fail = true;
      session.dispose();
      session = StudySessionController(
        repository,
        deckId: deck,
        loadSettings: () async {
          if (fail) throw StateError('学习设置读取失败');
          return StudySettings(dailyNewLimit: 0);
        },
      );
      await session.start();
      expect(session.current, isNull);
      expect(session.error, '学习设置读取失败');
      expect(session.isComplete, isFalse);
      fail = false;
      await session.start();
      expect(session.error, isNull);
      expect(session.isComplete, isTrue);
    },
  );
}
