import 'note.dart';

/// Stable indexes refer to stored options, never to shuffled display letters.
class ChoiceQuestion {
  ChoiceQuestion({
    required this.type,
    required this.prompt,
    required Iterable<String> options,
    required Iterable<int> correctIndexes,
    this.explanation = '',
    this.shuffle = false,
  }) : options = List.unmodifiable(options),
       correctIndexes = Set.unmodifiable(correctIndexes) {
    if (!type.isChoice) throw ArgumentError('请选择单选题或多选题');
    if (prompt.trim().isEmpty) throw ArgumentError('请填写题干');
    if (this.options.length < 2 || this.options.length > maxOptions) {
      throw ArgumentError('选择题需要 2–8 个选项');
    }
    if (this.options.any((option) => option.trim().isEmpty)) {
      throw ArgumentError('请填写每个选项，或删除空选项');
    }
    if (this.correctIndexes.any((i) => i < 0 || i >= this.options.length)) {
      throw ArgumentError('正确答案指向了不存在的选项');
    }
    if (type == NoteType.singleChoice && this.correctIndexes.length != 1) {
      throw ArgumentError('单选题需要选定一个正确答案');
    }
    if (type == NoteType.multipleChoice && this.correctIndexes.length < 2) {
      throw ArgumentError('多选题需要选定至少两个正确答案');
    }
  }

  static const maxOptions = 8;
  final NoteType type;
  final String prompt;
  final List<String> options;
  final Set<int> correctIndexes;
  final String explanation;
  final bool shuffle;

  factory ChoiceQuestion.fromFields(NoteType type, Map<String, String> fields) {
    final count = int.tryParse(fields['optionCount'] ?? '');
    final raw = (fields['correctAnswers'] ?? '').split(',');
    final answers = raw.map(int.tryParse).toList();
    if (count == null ||
        count < 2 ||
        count > maxOptions ||
        answers.any((i) => i == null) ||
        answers.toSet().length != answers.length ||
        !{'0', '1'}.contains(fields['shuffleOptions'])) {
      throw ArgumentError('选择题数据无效，请编辑并重新保存');
    }
    return ChoiceQuestion(
      type: type,
      prompt: fields['front'] ?? '',
      options: List.generate(count, (i) => fields['option$i'] ?? ''),
      correctIndexes: answers.cast<int>(),
      explanation: fields['back'] ?? '',
      shuffle: fields['shuffleOptions'] == '1',
    );
  }

  Map<String, String> toFields() => {
    'front': prompt,
    'back': explanation,
    'optionCount': '${options.length}',
    'correctAnswers': (correctIndexes.toList()..sort()).join(','),
    'shuffleOptions': shuffle ? '1' : '0',
    // Clear removed option fields when merging with existing source metadata.
    for (var i = 0; i < maxOptions; i++)
      'option$i': i < options.length ? options[i] : '',
  };

  bool isCorrect(Set<int> selected) =>
      selected.length == correctIndexes.length &&
      selected.containsAll(correctIndexes);
}
