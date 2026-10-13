/// Standard Anki deletions: {{c1::answer}} and {{c1::answer::hint}}.
/// Unsupported or malformed syntax remains visible for the user to correct.
class ClozeParser {
  static final _deletion = RegExp(
    r'\{\{c([1-9]\d*)::([^{}]+?)\}\}',
    dotAll: true,
  );

  List<int> indexes(String source) {
    final indexes = <int>{};
    for (final match in _deletion.allMatches(source)) {
      final index = int.tryParse(match.group(1)!);
      if (index != null) indexes.add(index);
    }
    return indexes.toList()..sort();
  }

  String renderQuestion(String source, int index) =>
      source.replaceAllMapped(_deletion, (match) {
        final body = match.group(2)!;
        final separator = body.indexOf('::');
        final answer = separator < 0 ? body : body.substring(0, separator);
        if (int.tryParse(match.group(1)!) != index) return answer;
        final hint = separator < 0 ? '' : body.substring(separator + 2);
        return hint.isEmpty ? '[…]' : '[$hint]';
      });

  String renderAnswer(String source, int index) =>
      source.replaceAllMapped(_deletion, (match) {
        final body = match.group(2)!;
        final separator = body.indexOf('::');
        return separator < 0 ? body : body.substring(0, separator);
      });
}
