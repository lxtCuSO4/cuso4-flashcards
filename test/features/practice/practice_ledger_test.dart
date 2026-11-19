import 'dart:convert';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_question.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_attempt.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/practice/data/practice_repository.dart';
import 'package:cuso4_flashcards/features/practice/data/practice_session_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PracticeSessionRepository sessions;
  late PracticeScope scope;
  final question = ChoiceQuestion(
    type: NoteType.singleChoice,
    prompt: '刷题记录',
    options: ['对', '错'],
    correctIndexes: [0],
  );
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final deck = await DeckRepository(db).createDeck('记录牌组');
    for (var i = 0; i < 2; i++) {
      await NoteRepository(db)
          .createChoiceNote(deckId: deck, question: question);
    }
    scope = PracticeScope(
      deckId: deck,
      choicesOnly: true,
      order: PracticeOrder.sequential,
    );
    sessions = PracticeSessionRepository(PracticeRepository(db));
  });
  tearDown(() => db.close());
  Future<PracticeSession> bind(PracticeSession session) =>
      sessions.bindQuestion(
        session,
        signature: jsonEncode(question.toFields()),
        isChoice: true,
        optionCount: 2,
      );

  test('real submission creates one independent event and retries do not add events', () async {
    var session = await bind(await sessions.open(scope));
    session = await sessions.submit(session, {1}, question: question);
    await sessions.submit(session, {0}, question: question);
    final events = (await db.select(db.appSettings).get())
        .where((s) => s.key.startsWith('practice:attempt:'))
        .toList();
    expect(events.length, 1);
    expect(jsonDecode(events.single.valueJson)['correct'], false);
    expect((await db.select(db.wrongQuestions).get()).single.wrongCount, 1);
    expect(await db.select(db.reviewLogs).get(), isEmpty);
  });

  test(
    'advancing keeps the previous submitted answer for the answer sheet',
    () async {
      var session = await bind(await sessions.open(scope));
      final cardId = session.cardId;
      session = await sessions.submit(session, {0}, question: question);
      session = await sessions.advance(session);
      final rows = (await db.select(db.appSettings).get())
          .where((s) => s.key == 'practice:card:${session.id}:$cardId')
          .toList();
      expect(rows.length, 1);
      final answer = jsonDecode(rows.single.valueJson);
      expect(answer['attempted'], true);
      expect(answer['selected'], [0]);
    },
  );

  test('viewing an explanation never creates a submitted event', () async {
    final session = await bind(await sessions.open(scope));
    await sessions.reveal(session, explanation: true);
    expect(
      (await db.select(db.appSettings).get()).where(
        (s) => s.key.startsWith('practice:attempt:'),
      ),
      isEmpty,
    );
    expect(await db.select(db.wrongQuestions).get(), isEmpty);
  });

  test(
    'jump restores drafts and answers without changing counters or logs',
    () async {
      var session = await bind(await sessions.open(scope));
      session = await sessions.submit(session, {1}, question: question);
      session = await sessions.advance(session);
      session = await bind(session);
      session = await sessions.saveAttempt(
        session,
        ChoiceAttemptSnapshot(selected: [0], order: [0, 1], attempted: false),
      );
      session = await sessions.jump(session, 0);
      expect(session.attempted, true);
      expect(session.selected, {1});
      session = await sessions.submit(session, {0}, question: question);
      session = await sessions.advance(session);
      expect(session.selected, {0});
      expect(session.attempted, false);
      expect(session.incorrect, 1);
      expect(
        (await db.select(db.appSettings).get())
            .where((s) => s.key.startsWith('practice:attempt:'))
            .length,
        1,
      );
    },
  );

  test(
    'jumping to the last question does not finish unanswered earlier questions',
    () async {
      var session = await sessions.open(scope);
      session = await sessions.jump(session, 1);
      session = await bind(session);
      session = await sessions.submit(session, {0}, question: question);
      session = await sessions.advance(session);
      expect(session.completed, false);
      expect(session.index, 0);
      session = await bind(session);
      session = await sessions.submit(session, {0}, question: question);
      session = await sessions.advance(session);
      session = await sessions.advance(session);
      expect(session.completed, true);
      session = await sessions.jump(session, 0);
      expect(session.roundFinished, true);
      expect(session.attempted, true);
      session = await sessions.showSummary(session);
      expect(session.completed, true);
      expect(session.correct, 2);
    },
  );

  test('legacy cursors preserve totals and mark unknown past answers explicitly', () async {
    var session = await sessions.open(scope);
    final queueRow = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals('${scope.key}:queue'))).getSingle();
    final queue = jsonDecode(queueRow.valueJson) as Map<String, dynamic>;
    queue['version'] = 1;
    final cursor = {
      ...session.copyWith(index: 1, correct: 1).cursor,
      'version': 1,
    };
    await db.customStatement(
      'UPDATE app_settings SET value_json = ? WHERE key = ?',
      [jsonEncode(queue), '${scope.key}:queue'],
    );
    await db.customStatement(
      'UPDATE app_settings SET value_json = ? WHERE key = ?',
      [jsonEncode(cursor), '${scope.key}:cursor'],
    );
    // Version 1 stored only the queue and current cursor, never per-card rows.
    await db.customStatement('DELETE FROM app_settings WHERE key GLOB ?', [
      'practice:card:${session.id}:*',
    ]);
    session = await sessions.open(scope);
    expect(session.index, 1);
    expect(session.correct, 1);
    expect(
      (await sessions.answers(session)).first.status,
      PracticeAnswerStatus.legacy,
    );
    session = await bind(await sessions.jump(session, 0));
    expect(session.legacyReview, true);
    await expectLater(
      sessions.submit(session, {0}, question: question),
      throwsStateError,
    );
    expect(
      (await db.select(db.appSettings).get()).where(
        (s) => s.key.startsWith('practice:attempt:'),
      ),
      isEmpty,
    );
  });

  test(
    'editing a skipped or viewed question removes its old summary count',
    () async {
      var session = await bind(await sessions.open(scope));
      session = await sessions.advance(session, skip: true);
      session = await sessions.jump(session, 0);
      session = await sessions.bindQuestion(
        session,
        signature: 'changed skipped question',
        isChoice: true,
        optionCount: 2,
      );
      expect(session.skipped, 0);
      session = await sessions.reveal(session);
      session = await sessions.advance(session);
      session = await sessions.jump(session, 0);
      expect(session.unanswered, 1);
      session = await sessions.bindQuestion(
        session,
        signature: 'changed viewed question',
        isChoice: true,
        optionCount: 2,
      );
      expect(session.unanswered, 0);
      expect(session.answerVisible, false);
    },
  );

  test(
    'new rounds discard obsolete answer snapshots but retain real events',
    () async {
      var session = await bind(await sessions.open(scope));
      session = await sessions.submit(session, {0}, question: question);
      final oldId = session.id;
      session = await sessions.open(scope, restart: true);
      final rows = await db.select(db.appSettings).get();
      expect(
        rows.where((s) => s.key.startsWith('practice:card:$oldId:')),
        isEmpty,
      );
      expect(
        rows.where((s) => s.key.startsWith('practice:attempt:')),
        hasLength(1),
      );
      expect(session.correct, 0);
    },
  );
}
