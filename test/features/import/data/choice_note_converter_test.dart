import 'package:cuso4_flashcards/features/decks/domain/choice_question.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/import/data/anki_collection_reader.dart';
import 'package:cuso4_flashcards/features/import/data/anki_note_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final converter = AnkiNoteConverter();
  AnkiConversionResult convert(
    List<String> names,
    List<String> values, {
    bool reverse = false,
  }) => converter.convert(
    AnkiNote(
      id: 1,
      modelId: 2,
      deckId: 3,
      isCloze: false,
      fields: values,
      tags: ['tag'],
    ),
    AnkiModel(id: 2, name: 'Custom', isCloze: false, fieldNames: names),
    [
      const AnkiCard(id: 1, noteId: 1, deckId: 3, ordinal: 0),
      if (reverse) const AnkiCard(id: 2, noteId: 1, deckId: 3, ordinal: 1),
    ],
  );

  test('Front/Back/Source creates choices and preserves explanation, tags and media', () {
    final result = convert(
      ['Front', 'Back', 'Source'],
      ['题干<br>A. <img src="a.png"><br>B. 乙', '<b>答案：A</b><br>解析：说明', '第一章'],
    ).note!;
    expect(result.type, NoteType.singleChoice);
    final question = ChoiceQuestion.fromFields(result.type, result.fields);
    expect(question.options.first, contains('a.png'));
    expect(question.explanation, allOf(contains('解析'), contains('来源：第一章')));
    expect(result.mediaNames, {'a.png'});
    expect(result.tags, ['tag']);
    expect(
      convert(['Front', 'Back'], ['题干<br>A. 甲<br>B. 乙', '答案：AB']).note!.type,
      NoteType.multipleChoice,
    );
  });

  test(
    'ambiguous choices retain the entire basic front/back and are counted',
    () {
      final result = convert(
        ['Front', 'Back'],
        ['【单选】题干<br>A. 甲<br>B. 乙', '答案：AB'],
      ).note!;
      expect(result.type, NoteType.basic);
      expect(result.choiceFallback, isTrue);
      expect(result.fields['front'], contains('A. 甲'));
      expect(result.fields['back'], '答案：AB');
      expect(
        convert(['Front', 'Back'], ['普通问答', '回答']).note!.choiceFallback,
        isFalse,
      );
    },
  );

  test('unique structured fields work in any order and preserve incomplete content as basic', () {
    final names = ['选项B', '答案', '题干', '选项A', '解析', '题型', '来源'];
    final values = ['乙', 'AB', '题目', '甲', '详细解析', '多选', '第二章'];
    final result = convert(names, values).note!;
    expect(result.type, NoteType.multipleChoice);
    final question = ChoiceQuestion.fromFields(result.type, result.fields);
    expect(question.options, ['甲', '乙']);
    expect(question.explanation, allOf(contains('详细解析'), contains('来源：第二章')));
    final invalid = convert(names, [
      '乙',
      '',
      '题目',
      '甲',
      '详细解析',
      '多选',
      '第二章',
    ]).note!;
    expect(invalid.type, NoteType.basic);
    expect(invalid.choiceFallback, isTrue);
    expect(invalid.fields['front'], contains('B. 乙'));
    expect(invalid.fields['back'], contains('详细解析'));
  });

  test('unknown extra fields, duplicate aliases and reverse cards remain unsupported', () {
    expect(
      convert(
        ['Front', 'Back'],
        ['题干<br>A. 甲<br>B. 乙', '答案：A'],
        reverse: true,
      ).skippedReason,
      'unsupportedTemplate',
    );
    expect(
      convert(
        ['Question', 'OptionA', 'OptionB', 'Answer', 'Other'],
        ['题干', '甲', '乙', 'A', 'other'],
      ).skippedReason,
      'unsupportedTemplate',
    );
    expect(
      convert(
        ['Question', 'Prompt', 'OptionA', 'OptionB', 'Answer'],
        ['题干', '题干', '甲', '乙', 'A'],
      ).skippedReason,
      'unsupportedTemplate',
    );
  });
}
