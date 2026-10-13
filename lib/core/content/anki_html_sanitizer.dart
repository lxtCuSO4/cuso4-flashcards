import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class SanitizedAnkiHtml {
  const SanitizedAnkiHtml(this.html, this.mediaNames);
  final String html;
  final Set<String> mediaNames;
}

class AnkiHtmlSanitizer {
  static const _elementEscape = HtmlEscape(HtmlEscapeMode.element);
  static const _attributeEscape = HtmlEscape(HtmlEscapeMode.attribute);
  static final _sound = RegExp(r'\[sound:([^\]\r\n]+)\]');
  static const _allowedTags = {
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
    'p',
    'div',
    'ul',
    'ol',
    'li',
    'blockquote',
    'code',
    'pre',
    'table',
    'thead',
    'tbody',
    'tr',
    'th',
    'td',
  };
  static const _blockedTags = {
    'script',
    'style',
    'iframe',
    'object',
    'embed',
    'link',
    'meta',
    'form',
    'input',
    'button',
    'video',
    'audio',
    'svg',
    'math',
  };

  SanitizedAnkiHtml sanitize(String source) {
    final html = StringBuffer();
    final mediaNames = <String>{};

    void writeText(String value) {
      var position = 0;
      for (final match in _sound.allMatches(value)) {
        html.write(
          _elementEscape.convert(value.substring(position, match.start)),
        );
        final name = match.group(1)!;
        if (_isLocalMediaName(name)) {
          mediaNames.add(name);
          html.write('[sound:${_elementEscape.convert(name)}]');
        }
        position = match.end;
      }
      html.write(_elementEscape.convert(value.substring(position)));
    }

    void visit(dom.Node node) {
      if (node is dom.Text) {
        writeText(node.data);
        return;
      }
      if (node is! dom.Element) return;
      final tag = node.localName ?? '';
      if (_blockedTags.contains(tag)) return;
      if (tag == 'br') {
        html.write('<br>');
        return;
      }
      if (tag == 'img') {
        final name = node.attributes['src'];
        if (name != null && _isLocalMediaName(name)) {
          mediaNames.add(name);
          html.write('<img src="${_attributeEscape.convert(name)}">');
        }
        return;
      }
      final allowed = _allowedTags.contains(tag);
      if (allowed) html.write('<$tag>');
      for (final child in node.nodes) {
        visit(child);
      }
      if (allowed) html.write('</$tag>');
    }

    for (final node in html_parser.parseFragment(source).nodes) {
      visit(node);
    }
    return SanitizedAnkiHtml(html.toString(), Set.unmodifiable(mediaNames));
  }

  bool _isLocalMediaName(String name) {
    if (name.isEmpty || name == '.' || name == '..') {
      return false;
    }
    if (name.contains('/') || name.contains('\\') || name.contains(':')) {
      return false;
    }
    if (name.contains('?') || name.contains('#')) {
      return false;
    }
    return !name.runes.any((code) => code < 0x20 || code == 0x7f);
  }
}
