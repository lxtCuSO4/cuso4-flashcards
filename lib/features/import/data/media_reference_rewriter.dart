import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

class MediaReferenceRewriter {
  static final _sound = RegExp(r'\[sound:([^\]\r\n]+)\]');

  String rewrite(String safeHtml, Map<String, String> hashesByName) {
    final fragment = html_parser.parseFragment(safeHtml);

    void visit(dom.Node node) {
      if (node is dom.Text) {
        node.data = node.data.replaceAllMapped(_sound, (match) {
          final hash = hashesByName[match.group(1)];
          return hash == null ? match.group(0)! : '[sound:media:$hash]';
        });
        return;
      }
      if (node is! dom.Element) return;
      if (node.localName == 'img') {
        final name = node.attributes['src'];
        final hash = hashesByName[name];
        if (hash != null) node.attributes['src'] = 'media:$hash';
      }
      for (final child in node.nodes) {
        visit(child);
      }
    }

    for (final node in fragment.nodes) {
      visit(node);
    }
    return fragment.outerHtml;
  }
}
