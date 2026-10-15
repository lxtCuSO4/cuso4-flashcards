import '../../../core/content/anki_html_sanitizer.dart';
import '../../decks/domain/cloze_parser.dart';
import '../../decks/domain/choice_recognizer.dart';
import '../../decks/domain/note.dart';
import 'anki_collection_reader.dart';

class ConvertedAnkiNote {
  const ConvertedAnkiNote({
    required this.type,
    required this.fields,
    required this.tags,
    required this.mediaNames,
    this.choiceFallback = false,
  });
  final NoteType type;
  final Map<String, String> fields;
  final List<String> tags;
  final Set<String> mediaNames;
  final bool choiceFallback;
}

class AnkiConversionResult {
  const AnkiConversionResult.converted(ConvertedAnkiNote converted)
    : note = converted,
      skippedReason = null;
  const AnkiConversionResult.skipped(this.skippedReason) : note = null;
  final ConvertedAnkiNote? note;
  final String? skippedReason;
}

class AnkiNoteConverter {
  AnkiNoteConverter({AnkiHtmlSanitizer? sanitizer})
    : _sanitizer = sanitizer ?? AnkiHtmlSanitizer();
  final AnkiHtmlSanitizer _sanitizer;
  final ClozeParser _cloze = ClozeParser();
  final ChoiceRecognizer _choices = ChoiceRecognizer();

  AnkiConversionResult convert(
    AnkiNote source,
    AnkiModel model,
    Iterable<AnkiCard> cards,
  ) {
    final sourceCards = cards.toList();
    if (source.modelId != model.id ||
        source.isCloze != model.isCloze ||
        source.fields.length != model.fieldNames.length ||
        sourceCards.isEmpty) {
      return const AnkiConversionResult.skipped('unsupportedTemplate');
    }
    final names = model.fieldNames
        .map((name) => name.trim().toLowerCase())
        .toList();
    // Support a known provenance field, not arbitrary Anki template execution.
    final hasSource =
        names.isNotEmpty && const ['source', '来源'].contains(names.last);
    final contentNames = hasSource ? names.sublist(0, names.length - 1) : names;
    final media = <String>{};
    String field(int index) {
      final safe = _sanitizer.sanitize(source.fields[index]);
      media.addAll(safe.mediaNames);
      return safe.html;
    }

    String withSource(String answer) {
      if (!hasSource) return answer;
      final sourceHtml = field(names.length - 1);
      if (sourceHtml.trim().isEmpty) return answer;
      return '$answer<div><small>来源：$sourceHtml</small></div>';
    }

    if (!model.isCloze) {
      if (sourceCards.length != 1 || sourceCards.single.ordinal != 0) {
        return const AnkiConversionResult.skipped('unsupportedTemplate');
      }
      final structured = _structuredFields(names);
      String front;
      String back;
      var typeHint = '';
      if (structured != null) {
        String value(String key) =>
            structured.containsKey(key) ? field(structured[key]!) : '';
        typeHint = structured.containsKey('type')
            ? source.fields[structured['type']!]
            : '';
        front = [
          value('prompt'),
          for (var i = 0; i < 8; i++)
            if (structured.containsKey('option$i'))
              '${String.fromCharCode(65 + i)}. ${value('option$i')}',
        ].join('<br>');
        final provenance = value('source');
        back =
            '答案：${value('answer')}<br>${value('explanation')}${provenance.trim().isEmpty ? '' : '<div><small>来源：$provenance</small></div>'}';
      } else {
        if (contentNames.length != 2 ||
            !_sameNames(
              contentNames,
              const ['front', 'back'],
              const ['正面', '背面'],
            )) {
          return const AnkiConversionResult.skipped('unsupportedTemplate');
        }
        front = field(0);
        back = withSource(field(1));
      }
      if (front.trim().isEmpty) {
        return const AnkiConversionResult.skipped('emptyFront');
      }
      final recognition = _choices.recognize(front, back, typeHint: typeHint);
      return AnkiConversionResult.converted(
        ConvertedAnkiNote(
          type: recognition.question?.type ?? NoteType.basic,
          fields:
              recognition.question?.toFields() ??
              {'front': front, 'back': back},
          tags: source.tags,
          mediaNames: Set.unmodifiable(media),
          choiceFallback:
              recognition.question == null &&
              (recognition.candidate || structured != null),
        ),
      );
    }

    if (contentNames.isEmpty ||
        contentNames.length > 2 ||
        !['text', '文字'].contains(contentNames.first) ||
        (contentNames.length == 2 &&
            !['back extra', 'extra', '背面额外'].contains(contentNames[1]))) {
      return const AnkiConversionResult.skipped('unsupportedTemplate');
    }
    final text = field(0);
    final extra = withSource(contentNames.length == 2 ? field(1) : '');
    final indexes = _cloze.indexes(text).toSet();
    final sourceIndexes = sourceCards.map((card) => card.ordinal + 1).toSet();
    if (indexes.isEmpty ||
        indexes.length != sourceIndexes.length ||
        !indexes.containsAll(sourceIndexes)) {
      return const AnkiConversionResult.skipped('unsupportedClozeCards');
    }
    return AnkiConversionResult.converted(
      ConvertedAnkiNote(
        type: NoteType.cloze,
        fields: {'text': text, 'extra': extra},
        tags: source.tags,
        mediaNames: Set.unmodifiable(media),
      ),
    );
  }

  Map<String, int>? _structuredFields(List<String> names) {
    final mapped = <String, int>{};
    const aliases = {
      'question': 'prompt',
      'prompt': 'prompt',
      'stem': 'prompt',
      '题干': 'prompt',
      'answer': 'answer',
      'correctanswer': 'answer',
      '答案': 'answer',
      '正确答案': 'answer',
      'explanation': 'explanation',
      '解析': 'explanation',
      'type': 'type',
      '题型': 'type',
      'source': 'source',
      '来源': 'source',
    };
    for (var i = 0; i < names.length; i++) {
      final option = RegExp(r'^(?:option|选项)([a-h])$').firstMatch(names[i]);
      final key = option == null
          ? aliases[names[i]]
          : 'option${option[1]!.codeUnitAt(0) - 97}';
      if (key == null || mapped.containsKey(key)) return null;
      mapped[key] = i;
    }
    if (!mapped.containsKey('prompt') ||
        !mapped.containsKey('answer') ||
        mapped.keys.where((k) => k.startsWith('option')).length < 2) {
      return null;
    }
    return mapped;
  }

  bool _sameNames(
    List<String> actual,
    List<String> first,
    List<String> second,
  ) {
    return _equal(actual, first) || _equal(actual, second);
  }

  bool _equal(List<String> left, List<String> right) {
    if (left.length != right.length) return false;
    for (var i = 0; i < left.length; i++) {
      if (left[i] != right[i]) return false;
    }
    return true;
  }
}
