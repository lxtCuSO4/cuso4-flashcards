import '../../../core/content/anki_html_sanitizer.dart';
import '../../decks/domain/cloze_parser.dart';
import '../../decks/domain/note.dart';
import 'anki_collection_reader.dart';

class ConvertedAnkiNote {
  const ConvertedAnkiNote({
    required this.type,
    required this.fields,
    required this.tags,
    required this.mediaNames,
  });
  final NoteType type;
  final Map<String, String> fields;
  final List<String> tags;
  final Set<String> mediaNames;
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
    final media = <String>{};
    String field(int index) {
      final safe = _sanitizer.sanitize(source.fields[index]);
      media.addAll(safe.mediaNames);
      return safe.html;
    }

    if (!model.isCloze) {
      if (names.length != 2 ||
          !_sameNames(names, const ['front', 'back'], const ['正面', '背面']) ||
          sourceCards.length != 1 ||
          sourceCards.single.ordinal != 0) {
        return const AnkiConversionResult.skipped('unsupportedTemplate');
      }
      final front = field(0);
      final back = field(1);
      if (front.trim().isEmpty) {
        return const AnkiConversionResult.skipped('emptyFront');
      }
      return AnkiConversionResult.converted(
        ConvertedAnkiNote(
          type: NoteType.basic,
          fields: {'front': front, 'back': back},
          tags: source.tags,
          mediaNames: Set.unmodifiable(media),
        ),
      );
    }

    if (names.isEmpty ||
        names.length > 2 ||
        !['text', '文字'].contains(names.first) ||
        (names.length == 2 &&
            !['back extra', 'extra', '背面额外'].contains(names[1]))) {
      return const AnkiConversionResult.skipped('unsupportedTemplate');
    }
    final text = field(0);
    final extra = names.length == 2 ? field(1) : '';
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
