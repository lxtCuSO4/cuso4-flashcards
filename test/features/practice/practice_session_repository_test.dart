import 'dart:convert';
import 'dart:io';

import 'package:cuso4_flashcards/app/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/backup/data/backup_archive.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_attempt.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_question.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/practice/data/practice_repository.dart';
import 'package:cuso4_flashcards/features/practice/data/practice_session_repository.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDownAll(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  late AppDatabase db;
  late PracticeRepository practice;
  late PracticeSessionRepository sessions;
  late int deck, other;
  late List<int> ids;
  final question = ChoiceQuestion(
    type: NoteType.singleChoice,
    prompt: '持久化题目',
    options: ['正确', '错误', '其他'],
    correctIndexes: [0],
    shuffle: true,
  );
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    practice = PracticeRepository(db);
    sessions = PracticeSessionRepository(practice);
    deck = await DeckRepository(db).createDeck('练习');
    other = await DeckRepository(db).createDeck('其他');
    for (var i = 0; i < 3; i++) {
      await NoteRepository(db)
          .createChoiceNote(deckId: deck, question: question);
    }
    await NoteRepository(db)
        .createChoiceNote(deckId: other, question: question);
    ids = (await db.select(db.cards).get()).map((c) => c.id).toList();
  });
  tearDown(() => db.close());
  PracticeScope scope({
    PracticeOrder order = PracticeOrder.sequential,
    bool favorites = false,
    bool wrong = false,
  }) => PracticeScope(
    deckId: deck,
    choicesOnly: true,
    order: order,
    favoritesOnly: favorites,
    wrongOnly: wrong,
  );
  Future<PracticeSession> bind(PracticeSession session) =>
      sessions.bindQuestion(
        session,
        signature: jsonEncode(question.toFields()),
        isChoice: true,
        optionCount: 3,
        shuffle: true,
      );

  test('entire scope is available beyond 500 cards', () async {
    final notes = NoteRepository(db);
    for (var i = 0; i < 501; i++) {
      await notes.createBasicNote(deckId: deck, front: '$i');
    }
    final round = await practice.sample(
      deckId: deck,
      includeChildren: true,
      order: PracticeOrder.sequential,
    );
    expect(round.cardIds.length, 504);
    expect(round.cardIds.toSet().length, 504);
  });

  test(
    'practice queues are not exposed as global appearance settings',
    () async {
      await sessions.open(scope());
      final container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      final subscription = container.listen(settingsProvider, (_, _) {});
      try {
        final values = await container
            .read(settingsProvider.future)
            .timeout(const Duration(seconds: 3));
        expect(
          values.keys.where((key) => key.startsWith('practice:')),
          isEmpty,
        );
      } finally {
        subscription.close();
        container.dispose();
      }
    },
  );

  test('round, shuffled options and draft survive database reopen and backup validation', () async {
    var current = await bind(
      await sessions.open(scope(order: PracticeOrder.random)),
    );
    final order = current.optionOrder;
    current = await sessions.saveAttempt(
      current,
      ChoiceAttemptSnapshot(selected: [1], order: order, attempted: false),
    );
    final root = await Directory('build/test-temp').create(recursive: true);
    final temp = await root.createTemp('practice-resume-');
    final file = File('${temp.path}/copy.sqlite');
    await db.customStatement(
      "VACUUM INTO '${file.path.replaceAll("'", "''")}'",
    );
    final reopened = AppDatabase(NativeDatabase(file));
    try {
      final restored = await PracticeSessionRepository(
        PracticeRepository(reopened),
      ).peek(scope(order: PracticeOrder.random));
      expect(restored!.round.cardIds, current.round.cardIds);
      expect(restored.optionOrder, order);
      expect(restored.selected, {1});
      expect(restored.attempted, false);
      await BackupArchive.validateDatabase(file);
    } finally {
      await reopened.close();
      await temp.delete(recursive: true);
    }
  });

  test(
    'submitted answers and counters restore without grading twice',
    () async {
      var current = await bind(await sessions.open(scope()));
      current = await sessions.submit(current, {1}, question: question);
      expect(current.incorrect, 1);
      expect(current.explanation, true);
      final restored = (await sessions.peek(scope()))!;
      expect(restored.attempted, true);
      expect(restored.selected, {1});
      final again = await sessions.submit(restored, {2}, question: question);
      expect(again.selected, {1});
      expect((await db.select(db.wrongQuestions).get()).single.wrongCount, 1);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      expect(
        (await db.select(db.cards).get()).every((c) => c.repetitions == 0),
        true,
      );
    },
  );

  test('sequential, random, favorites and other decks are isolated', () async {
    await StudyRepository(db).setFavorite(ids.first, true);
    var current = await bind(await sessions.open(scope()));
    current = await sessions.reveal(current);
    current = await sessions.advance(current);
    final random = await sessions.open(scope(order: PracticeOrder.random));
    final favorite = await sessions.open(scope(favorites: true));
    final different = await sessions.open(
      PracticeScope(deckId: other, choicesOnly: true),
    );
    expect(current.index, 1);
    expect(random.index, 0);
    expect(favorite.round.cardIds, [ids.first]);
    expect(different.round.cardIds, [ids.last]);
    expect((await sessions.peek(scope()))!.index, 1);
  });

  test(
    'correct removal from mistakes does not shift the saved queue',
    () async {
      await practice.submitChoice(ids[0], {1}, expectedQuestion: question);
      await practice.submitChoice(ids[1], {1}, expectedQuestion: question);
      var current = await bind(await sessions.open(scope(wrong: true)));
      current = await sessions.submit(current, {0}, question: question);
      expect((await db.select(db.wrongQuestions).get()).map((w) => w.cardId), [
        ids[1],
      ]);
      current = await sessions.advance(current);
      final restored = (await sessions.peek(scope(wrong: true)))!;
      expect(restored.cardId, ids[1]);
      expect(restored.round.cardIds, [ids[0], ids[1]]);
      expect(restored.correct, 1);
    },
  );

  test('unchanged content preserves attempt; edited content resets only current answer', () async {
    var current = await bind(await sessions.open(scope()));
    current = await sessions.submit(current, {1}, question: question);
    final unchanged = await bind(current);
    expect(unchanged.attempted, true);
    expect(unchanged.selected, {1});
    final changed = await sessions.bindQuestion(
      unchanged,
      signature: 'new question version',
      isChoice: true,
      optionCount: 2,
    );
    expect(changed.attempted, false);
    expect(changed.answerVisible, false);
    expect(changed.selected, isEmpty);
    expect(changed.incorrect, 0);
    expect(changed.index, current.index);
    expect((await db.select(db.wrongQuestions).get()).single.wrongCount, 1);
  });

  test(
    'explicit restart invalidates stale saves and picks up added cards',
    () async {
      final old = await bind(await sessions.open(scope()));
      await NoteRepository(db)
          .createChoiceNote(deckId: deck, question: question);
      expect((await sessions.open(scope())).round.cardIds.length, 3);
      final restarted = await sessions.open(scope(), restart: true);
      expect(restarted.round.cardIds.length, 4);
      expect(restarted.id, isNot(old.id));
      await expectLater(sessions.reveal(old), throwsStateError);
    },
  );
}
