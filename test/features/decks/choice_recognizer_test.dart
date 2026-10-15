import 'package:cuso4_flashcards/features/decks/domain/choice_recognizer.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final recognizer = ChoiceRecognizer();
  test('recognizes explicit answer without a question type and preserves HTML media', () {
    final result = recognizer.recognize(
      '<div>选择正确项<img src="media:question"></div><div><b>A.</b> <sub>甲</sub><img src="media:a"></div><div>B. 乙</div>',
      '<b>答案：A</b><br>解析：示例<img src="media:explanation"><div>来源：教材</div>',
    );
    expect(result.question!.type, NoteType.singleChoice);
    expect(result.question!.correctIndexes, {0});
    expect(result.question!.prompt, contains('media:question'));
    expect(
      result.question!.options[0],
      allOf(contains('<sub>甲</sub>'), contains('media:a')),
    );
    expect(result.question!.options[0], isNot(contains('A.')));
    expect(result.question!.explanation, contains('来源：教材'));
  });
  test('multiline options and spaced answer sets work without reading explanation as a type', () {
    final result = recognizer.recognize(
      '【多选】选择<br>A. 内容<br>续行<br>B. 内容<br>C. 内容',
      '<b>正确答案：A、C</b><br>解析：这里也讨论单选题。',
    );
    expect(result.question!.type, NoteType.multipleChoice);
    expect(result.question!.correctIndexes, {0, 2});
    expect(result.question!.options.first, contains('续行'));
    final inferred = recognizer.recognize('选择\nA. 甲\nB. 乙', 'Answer: AB');
    expect(inferred.question!.type, NoteType.multipleChoice);
  });
  test('refuses missing, conflicting, duplicate or out-of-range answers and malformed options', () {
    for (final pair in [
      ('选择<br>A. 甲<br>B. 乙', '解析：应该理解 A 和 B'),
      ('【单选题】选择<br>A. 甲<br>B. 乙', '答案：AB'),
      ('【多选】选择<br>A. 甲<br>B. 乙', '答案：A'),
      ('选择<br>A. 甲<br>B. 乙', '答案：AA'),
      ('选择<br>A. 甲<br>B. 乙', '答案：C'),
      ('选择<br>A. 甲<br>C. 乙', '答案：A'),
      ('选择<br>A. <br>B. 乙', '答案：A'),
      ('选择<br>A. 甲<br>B. 乙', '答案：A<br>正确答案：B'),
      ('选择<br>A. 甲<br>B. 乙', '答案：A 或 B'),
    ]) {
      final result = recognizer.recognize(pair.$1, pair.$2);
      expect(result.question, isNull, reason: '$pair');
      expect(result.candidate, isTrue, reason: '$pair');
    }
    expect(recognizer.recognize('解释数据库', '这是普通问答').candidate, isFalse);
  });
}
