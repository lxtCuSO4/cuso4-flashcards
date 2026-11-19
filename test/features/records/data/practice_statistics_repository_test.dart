import 'dart:convert';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_question.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/practice/data/practice_repository.dart';
import 'package:cuso4_flashcards/features/practice/data/practice_session_repository.dart';
import 'package:cuso4_flashcards/features/records/data/practice_statistics_repository.dart';
import 'package:cuso4_flashcards/features/records/data/statistics_repository.dart';
import 'package:cuso4_flashcards/features/records/domain/daily_statistics.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PracticeSessionRepository sessions;
  late PracticeScope scope;
  late DateTime now;
  final question = ChoiceQuestion(
    type: NoteType.singleChoice,
    prompt: '<b>题干摘要</b>',
    options: ['对', '错'],
    correctIndexes: [0],
  );
  setUp(() async {
    now = DateTime.utc(2026, 11, 19, 18, 30);
    db = AppDatabase(NativeDatabase.memory());
    final deck = await DeckRepository(db).createDeck('统计牌组');
    for (var i = 0; i < 2; i++) {
      await NoteRepository(db)
          .createChoiceNote(deckId: deck, question: question);
    }
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'studyDayOffsetMinutes',
            valueJson: '480',
          ),
        );
    sessions = PracticeSessionRepository(
      PracticeRepository(db),
      clock: () => now,
    );
    scope = PracticeScope(
      deckId: deck,
      choicesOnly: true,
      order: PracticeOrder.sequential,
    );
  });
  tearDown(() => db.close());

  Future<PracticeSession> bind(PracticeSession s) => sessions.bindQuestion(
    s,
    signature: jsonEncode(question.toFields()),
    isChoice: true,
    optionCount: 2,
  );

  test(
    'practice totals use the same study day without writing formal statistics',
    () async {
      var s = await bind(await sessions.open(scope));
      s = await sessions.submit(s, {0}, question: question, elapsedMs: 62000);
      await sessions.submit(s, {1}, question: question);
      s = await bind(await sessions.advance(s));
      await sessions.submit(s, {1}, question: question, elapsedMs: 1000);
      final repo = PracticeStatisticsRepository(
        db,
        clock: () => DateTime.utc(2026, 11, 20, 10),
      );
      final stats = await repo.load();
      expect(stats.today, DateTime.utc(2026, 11, 20));
      expect(stats.summary.answered, 2);
      expect(stats.summary.correct, 1);
      expect(stats.summary.wrong, 1);
      expect(stats.summary.accuracy, .5);
      expect(stats.summary.elapsedMs, 63000);
      final history = await repo.dayDetails(DateTime.utc(2026, 11, 20), 480);
      expect(history.length, 2);
      expect(history.first['prompt'], '题干摘要');
      final formal = await StatisticsRepository(
        db,
        clock: () => DateTime.utc(2026, 11, 20),
      ).load();
      expect(formal.summary.reviewCount, 0);
      expect(formal.activeDays, 0);
    },
  );

  test(
    'calendar can show older days while period summary excludes them',
    () async {
      var s = await bind(await sessions.open(scope));
      await sessions.submit(s, {0}, question: question);
      now = DateTime.utc(2026, 11, 1, 2);
      s = await bind(await sessions.open(scope, restart: true));
      await sessions.submit(s, {0}, question: question);
      final repo = PracticeStatisticsRepository(
        db,
        clock: () => DateTime.utc(2026, 11, 20, 10),
      );
      final week = await repo.load();
      expect(week.summary.answered, 1);
      expect(week.days[DateTime.utc(2026, 11, 1)]!.answered, 1);
      expect(
        (await repo.load(period: StatisticsPeriod.all)).summary.answered,
        2,
      );
      expect((await repo.dayDetails(DateTime.utc(2026, 11, 2), 480)), isEmpty);
    },
  );
}
