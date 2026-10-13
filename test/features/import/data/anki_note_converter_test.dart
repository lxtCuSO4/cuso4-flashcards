import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/import/data/anki_collection_reader.dart';
import 'package:cuso4_flashcards/features/import/data/anki_note_converter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final converter = AnkiNoteConverter();
  const basic = AnkiModel(
    id: 1,
    name: 'Basic',
    isCloze: false,
    fieldNames: ['Front', 'Back'],
  );
  const cloze = AnkiModel(
    id: 2,
    name: 'Cloze',
    isCloze: true,
    fieldNames: ['Text', 'Back Extra'],
  );

  AnkiNote note(int modelId, List<String> fields) => AnkiNote(
    id: 10,
    modelId: modelId,
    deckId: 3,
    isCloze: modelId == 2,
    fields: fields,
    tags: const ['chemistry'],
  );
  AnkiCard card(int ordinal) =>
      AnkiCard(id: 20 + ordinal, noteId: 10, deckId: 3, ordinal: ordinal);

  test('maps a standard basic note and its local media', () {
    final result = converter.convert(
      note(1, ['<b>CuSO4</b><img src="salt.png">', '硫酸铜']),
      basic,
      [card(0)],
    );
    expect(result.skippedReason, isNull);
    expect(result.note!.type, NoteType.basic);
    expect(result.note!.fields, {
      'front': '<b>CuSO4</b><img src="salt.png">',
      'back': '硫酸铜',
    });
    expect(result.note!.mediaNames, {'salt.png'});
    expect(result.note!.tags, ['chemistry']);
  });

  test('maps all standard cloze ordinals to one local note', () {
    final result = converter.convert(
      note(2, ['{{c1::blue}} and {{c2::water}}', '[sound:clip.mp3]']),
      cloze,
      [card(0), card(1)],
    );
    expect(result.note!.type, NoteType.cloze);
    expect(result.note!.fields['text'], '{{c1::blue}} and {{c2::water}}');
    expect(result.note!.mediaNames, {'clip.mp3'});
  });

  test('skips ambiguous basic templates rather than mis-mapping fields', () {
    final result = converter.convert(note(1, ['front', 'back']), basic, [
      card(0),
      card(1),
    ]);
    expect(result.note, isNull);
    expect(result.skippedReason, 'unsupportedTemplate');
  });
}
