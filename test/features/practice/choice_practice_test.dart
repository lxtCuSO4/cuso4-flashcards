import 'dart:convert';
import 'dart:io';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_question.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/practice/data/practice_repository.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:cuso4_flashcards/features/study/domain/scheduler.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  late AppDatabase db;
  late PracticeRepository practice;
  bool originalClosed = false;
  late int deck, child, single, multi, basic;
  final one = ChoiceQuestion(
    type: NoteType.singleChoice,
    prompt: '单选',
    options: ['甲', '乙', '丙'],
    correctIndexes: [1],
  );
  final many = ChoiceQuestion(
    type: NoteType.multipleChoice,
    prompt: '多选',
    options: ['甲', '乙', '丙'],
    correctIndexes: [0, 2],
  );
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    originalClosed = false;
    practice = PracticeRepository(db);
    deck = await DeckRepository(db).createDeck('试题');
    child = await DeckRepository(db).createDeck('子章', parentId: deck);
    final notes = NoteRepository(db);
    await notes.createBasicNote(deckId: deck, front: '普通卡');
    await notes.createChoiceNote(deckId: deck, question: one);
    await notes.createChoiceNote(deckId: child, question: many);
    final cards = await db.select(db.cards).get();
    basic = cards[0].id;
    single = cards[1].id;
    multi = cards[2].id;
  });
  tearDown(() async {
    if (!originalClosed) await db.close();
  });

  Future<List<Map<String, Object?>>> schedule() async => [
    for (final table in ['cards', 'review_logs', 'favorites'])
      for (final row in await db.customSelect('SELECT * FROM $table').get())
        row.data,
  ];

  test('wrong -> wrong -> correct removes; later wrong reenters without touching schedule or favorites', () async {
    await StudyRepository(db).setFavorite(single, true);
    final before = await schedule();
    expect(
      await practice.submitChoice(single, {0}, expectedQuestion: one),
      false,
    );
    expect(
      await practice.submitChoice(single, {2}, expectedQuestion: one),
      false,
    );
    expect((await db.select(db.wrongQuestions).get()).single.wrongCount, 2);
    expect(
      await practice.submitChoice(single, {1}, expectedQuestion: one),
      true,
    );
    expect(await db.select(db.wrongQuestions).get(), isEmpty);
    await practice.submitChoice(single, {0}, expectedQuestion: one);
    expect((await db.select(db.wrongQuestions).get()).single.wrongCount, 1);
    expect(await schedule(), before);
  });

  test('multiple choice requires exact set; invalid or stale submissions do not clear mistakes', () async {
    expect(
      await practice.submitChoice(multi, {0}, expectedQuestion: many),
      false,
    );
    expect(
      await practice.submitChoice(multi, {0, 1, 2}, expectedQuestion: many),
      false,
    );
    await expectLater(
      practice.submitChoice(multi, {}, expectedQuestion: many),
      throwsArgumentError,
    );
    final changed = ChoiceQuestion(
      type: NoteType.multipleChoice,
      prompt: '题目已修改',
      options: many.options,
      correctIndexes: [0, 2],
    );
    await expectLater(
      practice.submitChoice(multi, {0, 2}, expectedQuestion: changed),
      throwsStateError,
    );
    expect((await db.select(db.wrongQuestions).get()).single.wrongCount, 2);
    expect(
      await practice.submitChoice(multi, {2, 0}, expectedQuestion: many),
      true,
    );
    expect(await db.select(db.wrongQuestions).get(), isEmpty);
  });

  test('sequential choice scope, wrong scope and favorite scope are independent snapshots', () async {
    final round = await practice.sample(
      deckId: deck,
      includeChildren: true,
      count: 500,
      choicesOnly: true,
      order: PracticeOrder.sequential,
    );
    expect(round.cardIds, [single, multi]);
    expect(
      (await practice.sample(
        deckId: deck,
        includeChildren: false,
        count: 500,
        choicesOnly: true,
      )).cardIds,
      [single],
    );
    await practice.submitChoice(multi, {0}, expectedQuestion: many);
    expect(
      (await practice.sample(
        includeChildren: true,
        count: 500,
        wrongOnly: true,
      )).cardIds,
      [multi],
    );
    expect(
      (await practice.sample(
        deckId: deck,
        includeChildren: false,
        count: 500,
        wrongOnly: true,
      )).cardIds,
      isEmpty,
    );
    await StudyRepository(db).setFavorite(single, true);
    expect(
      (await practice.sample(
        includeChildren: true,
        count: 500,
        favoritesOnly: true,
        choicesOnly: true,
      )).cardIds,
      [single],
    );
    await practice.submitChoice(multi, {0, 2}, expectedQuestion: many);
    expect(round.cardIds, [single, multi]);
    expect(
      (await practice.sample(
        includeChildren: true,
        count: 500,
        wrongOnly: true,
      )).cardIds,
      isEmpty,
    );
  });

  test(
    'choice cards are excluded from queue, availability and defensive rating',
    () async {
      final study = StudyRepository(db);
      expect((await study.loadQueue()).map((c) => c.id), [basic]);
      expect((await study.loadAvailability()).newCards, 1);
      final before = await schedule();
      await expectLater(
        study.rateCard(await study.getCard(single), ReviewRating.good),
        throwsStateError,
      );
      expect(await schedule(), before);
    },
  );

  test('deleting notes cascades wrong questions', () async {
    await practice.submitChoice(single, {0}, expectedQuestion: one);
    final card = await StudyRepository(db).getCard(single);
    await NoteRepository(db).deleteNote(card.noteId);
    expect(await db.select(db.wrongQuestions).get(), isEmpty);
  });

  test(
    'version 1 database upgrades without changing existing cards or favorites',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lunar_migration_',
      );
      final file = File('${directory.path}/legacy.sqlite');
      AppDatabase? upgraded;
      try {
        await StudyRepository(db).setFavorite(single, true);
        await db.customStatement('VACUUM INTO ?', [file.path]);
        final old = sqlite.sqlite3.open(file.path);
        old.execute('DROP TABLE wrong_questions');
        old.execute('PRAGMA user_version = 1');
        final before = jsonEncode(
          old
              .select('SELECT * FROM cards')
              .map((r) => r.values.toList())
              .toList(),
        );
        old.close();
        await db.close();
        originalClosed = true;
        upgraded = AppDatabase(NativeDatabase(file));
        expect(await upgraded.select(upgraded.wrongQuestions).get(), isEmpty);
        expect(
          (await upgraded.select(upgraded.favorites).get()).single.cardId,
          single,
        );
        final after = await upgraded.customSelect('SELECT * FROM cards').get();
        expect(
          jsonEncode(after.map((r) => r.data.values.toList()).toList()),
          before,
        );
        expect(
          (await upgraded.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          2,
        );
      } finally {
        await upgraded?.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
