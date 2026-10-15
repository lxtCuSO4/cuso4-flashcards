import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'choice_question.dart';
import 'note.dart';

class ChoiceRecognition {
  const ChoiceRecognition({this.question, this.candidate = false});
  final ChoiceQuestion? question;
  final bool candidate;
}

/// Only converts a complete question with an explicit, unambiguous answer key.
/// The answer explanation is preserved verbatim, including provenance/media.
class ChoiceRecognizer {
  static final _option = RegExp(r'^\s*(?:([A-H])[.．、:：)）]|[（(]([A-H])[)）])\s*');
  static final _answer = RegExp(
    r'^\s*(?:正确答案|参考答案|答案|correct\s*answer|answer)\s*[：:]\s*(.*?)\s*$',
    caseSensitive: false,
  );
  static final _marker = RegExp(
    r'[【\[（(]\s*(单选(?:题)?|多选(?:题)?)\s*[】\]）)]|^\s*(单选题|多选题)\s*[：:]',
    multiLine: true,
  );

  ChoiceRecognition recognize(
    String front,
    String back, {
    String typeHint = '',
  }) {
    final lines = _lines(front);
    final starts = <(int, RegExpMatch)>[];
    for (var i = 0; i < lines.length; i++) {
      final match = _option.firstMatch(lines[i].text);
      if (match != null) starts.add((i, match));
    }
    final promptLines = starts.isEmpty
        ? lines
        : lines.sublist(0, starts.first.$1);
    final promptText = promptLines.map((l) => l.text).join('\n');
    final markerTypes = _marker
        .allMatches(promptText)
        .map(
          (m) => (m[1] ?? m[2])!.startsWith('单')
              ? NoteType.singleChoice
              : NoteType.multipleChoice,
        )
        .toSet();
    final hint = typeHint.trim().toLowerCase();
    if ([
      '单选',
      '单选题',
      'single',
      'singlechoice',
      'single choice',
    ].contains(hint)) {
      markerTypes.add(NoteType.singleChoice);
    }
    if ([
      '多选',
      '多选题',
      'multiple',
      'multiplechoice',
      'multiple choice',
    ].contains(hint)) {
      markerTypes.add(NoteType.multipleChoice);
    }
    final candidate = starts.length >= 2 || markerTypes.isNotEmpty;
    const refused = ChoiceRecognition(candidate: true);
    if (!candidate) return const ChoiceRecognition();
    if (markerTypes.length > 1 ||
        starts.length < 2 ||
        starts.length > ChoiceQuestion.maxOptions) {
      return refused;
    }
    if (!_hasContent(promptLines.map((l) => l.markup).join())) return refused;
    final options = <String>[];
    for (var position = 0; position < starts.length; position++) {
      final (lineIndex, match) = starts[position];
      if ((match[1] ?? match[2]) != String.fromCharCode(65 + position)) {
        return refused;
      }
      final end = position + 1 == starts.length
          ? lines.length
          : starts[position + 1].$1;
      final option = [
        _removePrefix(lines[lineIndex].markup, match.end),
        ...lines.sublist(lineIndex + 1, end).map((l) => l.markup),
      ].join('<br>');
      if (!_hasContent(option)) return refused;
      options.add(option);
    }
    final answers = _lines(back)
        .map((l) => _answer.firstMatch(l.text))
        .whereType<RegExpMatch>()
        .toList();
    if (answers.length != 1) return refused;
    final letters = answers.single[1]!.toUpperCase().replaceAll(
      RegExp(r'[\s,，、;；/()（）\[\]【】]'),
      '',
    );
    if (!RegExp(r'^[A-H]{1,8}$').hasMatch(letters)) return refused;
    final indexes = letters.codeUnits.map((c) => c - 65).toSet();
    if (indexes.length != letters.length ||
        indexes.any((i) => i >= options.length)) {
      return refused;
    }
    final inferred = indexes.length == 1
        ? NoteType.singleChoice
        : NoteType.multipleChoice;
    if (markerTypes.isNotEmpty && markerTypes.single != inferred) {
      return refused;
    }
    return ChoiceRecognition(
      candidate: true,
      question: ChoiceQuestion(
        type: inferred,
        prompt: promptLines.map((l) => l.markup).join('<br>'),
        options: options,
        correctIndexes: indexes,
        explanation: back,
      ),
    );
  }

  bool _hasContent(String source) {
    final fragment = html.parseFragment(source);
    return (fragment.text ?? '').trim().isNotEmpty ||
        fragment.querySelector('img[src]') != null;
  }

  String _removePrefix(String source, int remaining) {
    final fragment = html.parseFragment(source);
    void visit(dom.Node node) {
      if (remaining == 0) return;
      if (node is dom.Text) {
        final count = remaining < node.data.length
            ? remaining
            : node.data.length;
        node.data = node.data.substring(count);
        remaining -= count;
      } else {
        for (final child in node.nodes) {
          visit(child);
        }
      }
    }

    visit(fragment);
    return fragment.nodes
        .map(
          (n) => n is dom.Element
              ? n.outerHtml
              : n is dom.Text
              ? const HtmlEscape(HtmlEscapeMode.element).convert(n.data)
              : '',
        )
        .join();
  }

  // Split at visible line boundaries while reopening inline wrappers, so an
  // option letter wrapped in <b> and an image on its next line stay intact.
  List<_ChoiceLine> _lines(String source) {
    final result = <_ChoiceLine>[];
    final tags = <String>[];
    var markup = StringBuffer();
    var text = StringBuffer();
    var image = false;
    void flush() {
      if (text.toString().trim().isNotEmpty || image) {
        result.add(
          _ChoiceLine(
            '$markup${tags.reversed.map((t) => '</$t>').join()}',
            text.toString(),
          ),
        );
      }
      markup = StringBuffer(tags.map((t) => '<$t>').join());
      text = StringBuffer();
      image = false;
    }

    void visit(dom.Node node, int depth) {
      if (depth > 64) return;
      if (node is dom.Text) {
        final parts = node.data.split(RegExp(r'\r\n?|\n'));
        for (var i = 0; i < parts.length; i++) {
          if (i > 0) flush();
          markup.write(
            const HtmlEscape(HtmlEscapeMode.element).convert(parts[i]),
          );
          text.write(parts[i]);
        }
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName;
      if (const {
        'script',
        'style',
        'iframe',
        'object',
        'embed',
        'form',
        'input',
        'button',
        'svg',
        'math',
        'video',
        'audio',
      }.contains(tag)) {
        return;
      }
      if (tag == 'br' || tag == 'hr') {
        flush();
        return;
      }
      if (tag == 'img') {
        markup.write(node.outerHtml);
        image = true;
        return;
      }
      final block = const {
        'div',
        'p',
        'li',
        'ul',
        'ol',
        'table',
        'thead',
        'tbody',
        'tr',
        'blockquote',
        'pre',
        'h1',
        'h2',
        'h3',
        'h4',
      }.contains(tag);
      if (block) flush();
      final inline = const {
        'b',
        'strong',
        'i',
        'em',
        'u',
        's',
        'sub',
        'sup',
        'small',
        'span',
        'code',
      }.contains(tag);
      if (inline) {
        markup.write('<$tag>');
        tags.add(tag!);
      }
      for (final child in node.nodes) {
        visit(child, depth + 1);
      }
      if (inline) {
        markup.write('</$tag>');
        tags.removeLast();
      }
      if (block) flush();
    }

    for (final node in html.parseFragment(source).nodes) {
      visit(node, 0);
    }
    flush();
    return result;
  }
}

class _ChoiceLine {
  const _ChoiceLine(this.markup, this.text);
  final String markup, text;
}
