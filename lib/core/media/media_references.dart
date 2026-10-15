import 'package:html/parser.dart' as html;

final _hash = RegExp(r'^media:([a-f0-9]{64})$');
final _sound = RegExp(r'\[sound:media:([a-f0-9]{64})\]');

/// Counts each local asset once per note, including legacy sound references.
Set<String> mediaReferences(Map<String, String> fields) {
  final result = <String>{};
  for (final value in fields.values) {
    final fragment = html.parseFragment(value);
    for (final image in fragment.querySelectorAll('img')) {
      final match = _hash.firstMatch(image.attributes['src'] ?? '');
      if (match != null) result.add(match[1]!);
    }
    for (final match in _sound.allMatches(fragment.text ?? '')) {
      result.add(match[1]!);
    }
  }
  return result;
}
