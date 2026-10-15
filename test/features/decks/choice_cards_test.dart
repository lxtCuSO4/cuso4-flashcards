import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_question.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:cuso4_flashcards/features/study/domain/scheduler.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

ChoiceQuestion question({
  NoteType type = NoteType.singleChoice,
  List<String> options = const ['进程', '线程', '程序'],
  Set<int> answers = const {1},
  bool shuffle = false,
}) => ChoiceQuestion(
  type: type,
  prompt: '操作系统的调度单位是？',
  options: options,
  correctIndexes: answers,
  explanation: '线程是调度单位。',
  shuffle: shuffle,
);

void main() {
  test(
    'choice field round-trip preserves stable answers and removed slots',
    () {
      final original = question(shuffle: true);
      final fields = original.toFields();
      final parsed = ChoiceQuestion.fromFields(NoteType.singleChoice, fields);
      expect(parsed.options, original.options);
      expect(parsed.correctIndexes, {1});
      expect(parsed.shuffle, isTrue);
      expect(fields['option7'], '');
      expect(parsed.isCorrect({1}), isTrue);
      expect(parsed.isCorrect({}), isFalse);
      expect(parsed.isCorrect({0, 1}), isFalse);
    },
  );

  test('multiple choice requires exact set, regardless of order', () {
    final item = question(type: NoteType.multipleChoice, answers: {0, 2});
    expect(item.isCorrect({2, 0}), isTrue);
    for (final answer in [
      <int>{},
      {0},
      {0, 1, 2},
      {1, 2},
      {0, 3},
    ]) {
      expect(item.isCorrect(answer), isFalse);
    }
  });

  test('invalid option counts, blanks and answer indexes are rejected', () {
    expect(() => question(options: ['one']), throwsArgumentError);
    expect(() => question(options: ['one', ' ']), throwsArgumentError);
    expect(() => question(answers: {}), throwsArgumentError);
    expect(() => question(answers: {0, 1}), throwsArgumentError);
    expect(() => question(answers: {3}), throwsArgumentError);
    expect(() => question(type: NoteType.multipleChoice), throwsArgumentError);
    final fields = question().toFields()..['correctAnswers'] = '1,1';
    expect(
      () => ChoiceQuestion.fromFields(NoteType.singleChoice, fields),
      throwsArgumentError,
    );
  });

  test(
    'both types create one card; editing preserves rated card and favorite',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final deck = await DeckRepository(db).createDeck('选择题');
      final notes = NoteRepository(db);
      final study = StudyRepository(db);
      final single = await notes.createChoiceNote(
        deckId: deck,
        question: question(),
      );
      await notes.createChoiceNote(
        deckId: deck,
        question: question(type: NoteType.multipleChoice, answers: {0, 2}),
      );
      expect(await db.select(db.cards).get(), hasLength(2));
      expect((await notes.getNote(single)).type, NoteType.singleChoice);
      final before = (await study.loadQueue()).first;
      final receipt = await study.rateCard(before, ReviewRating.good);
      await study.setFavorite(before.id, true);
      final note = await notes.getNote(single);
      await notes.updateNote(
        Note(
          id: note.id,
          deckId: note.deckId,
          type: note.type,
          fields: question(options: ['进程', '线程']).toFields(),
          tags: ['调度'],
          createdAtUtc: note.createdAtUtc,
          modifiedAtUtc: DateTime.now(),
        ),
      );
      final after = await study.getCard(before.id);
      expect(after.dueAtUtc, receipt.after.dueAtUtc);
      expect(after.repetitions, receipt.after.repetitions);
      expect(after.isFavorite, isTrue);
      expect(await db.select(db.reviewLogs).get(), hasLength(1));
      expect(
        ChoiceQuestion.fromFields(
          note.type,
          (await notes.getNote(single)).fields,
        ).options,
        hasLength(2),
      );
    },
  );
}
