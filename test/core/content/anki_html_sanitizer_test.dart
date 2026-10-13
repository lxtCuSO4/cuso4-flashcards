import 'package:cuso4_flashcards/core/content/anki_html_sanitizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final sanitizer = AnkiHtmlSanitizer();

  test('keeps simple formatting and local media references', () {
    final result = sanitizer.sanitize(
      '<b>CuSO4</b><br><img src="salt.png">[sound:pronunciation.mp3]',
    );
    expect(
      result.html,
      '<b>CuSO4</b><br><img src="salt.png">[sound:pronunciation.mp3]',
    );
    expect(result.mediaNames, {'salt.png', 'pronunciation.mp3'});
  });

  test('removes scripts, event handlers and remote resources', () {
    final result = sanitizer.sanitize(
      '<script>alert(1)</script><b onclick="x()">safe</b>'
      '<img src="https://example.com/a.png"><img src="data:image/png;base64,abc">'
      '<a href="javascript:alert(1)">text</a>',
    );
    expect(result.html, '<b>safe</b>text');
    expect(result.mediaNames, isEmpty);
  });

  test('rejects media paths while preserving escaped text', () {
    final result = sanitizer.sanitize(
      'A &amp; B<img src="../private.png">[sound:../private.mp3]',
    );
    expect(result.html, 'A &amp; B');
    expect(result.mediaNames, isEmpty);
  });
}
