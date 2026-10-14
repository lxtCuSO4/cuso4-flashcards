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

  test('maps OS basic fields and preserves sanitized Source on the back', () {
    const model = AnkiModel(
      id: 1,
      name: 'OS 基础问答',
      isCloze: false,
      fieldNames: ['Front', 'Back', 'Source'],
    );
    final result = converter.convert(
      note(1, ['问题', '答案', '<b>教材</b><script>alert(1)</script>']),
      model,
      [card(0)],
    );
    expect(result.skippedReason, isNull);
    expect(result.note!.fields, {
      'front': '问题',
      'back': '答案<div><small>来源：<b>教材</b></small></div>',
    });
  });

  test('maps OS cloze Source without changing text or card indexes', () {
    const model = AnkiModel(
      id: 2,
      name: 'OS 填空',
      isCloze: true,
      fieldNames: ['Text', 'Source'],
    );
    final result = converter.convert(
      note(2, ['{{c1::进程}}与{{c2::线程}}', '第二章']),
      model,
      [card(0), card(1)],
    );
    expect(result.skippedReason, isNull);
    expect(result.note!.fields, {
      'text': '{{c1::进程}}与{{c2::线程}}',
      'extra': '<div><small>来源：第二章</small></div>',
    });
  });

  test('preserves Back Extra and local images in optional cloze Source', () {
    const model = AnkiModel(
      id: 2,
      name: 'Cloze with Source',
      isCloze: true,
      fieldNames: ['Text', 'Back Extra', 'Source'],
    );
    final result = converter.convert(
      note(2, [
        '{{c1::答案}}',
        '补充',
        '<img src="source.png" onerror="alert(1)"><img src="https://x/y">',
      ]),
      model,
      [card(0)],
    );
    expect(result.skippedReason, isNull);
    expect(
      result.note!.fields['extra'],
      '补充<div><small>来源：<img src="source.png"></small></div>',
    );
    expect(result.note!.mediaNames, {'source.png'});
  });

  test('empty Source does not add a source label', () {
    const model = AnkiModel(
      id: 1,
      name: 'Basic with Source',
      isCloze: false,
      fieldNames: ['Front', 'Back', 'Source'],
    );
    final result = converter.convert(
      note(1, ['front', 'back', ' <script>ignored</script> ']),
      model,
      [card(0)],
    );
    expect(result.skippedReason, isNull);
    expect(result.note!.fields['back'], 'back');
  });

  test('accepts the Chinese provenance alias on Chinese basic fields', () {
    const model = AnkiModel(
      id: 1,
      name: '基础卡',
      isCloze: false,
      fieldNames: ['正面', '背面', '来源'],
    );
    final result = converter.convert(note(1, ['问题', '答案', '教材']), model, [
      card(0),
    ]);
    expect(result.skippedReason, isNull);
    expect(result.note!.fields['back'], contains('来源：教材'));
  });

  test('still rejects unknown or repeated supplementary fields', () {
    for (final (isCloze, names, fields) in [
      (false, ['Front', 'Back', 'Other'], ['front', 'back', 'other']),
      (false, ['Front', 'Back', 'Source', 'Other'], ['f', 'b', 's', 'o']),
      (true, ['Text', 'Other'], ['{{c1::answer}}', 'other']),
      (true, ['Text', 'Source', 'Source'], ['{{c1::answer}}', 's', 's']),
    ]) {
      final id = isCloze ? 2 : 1;
      final result = converter.convert(
        note(id, fields),
        AnkiModel(id: id, name: 'Unknown', isCloze: isCloze, fieldNames: names),
        [card(0)],
      );
      expect(result.skippedReason, 'unsupportedTemplate', reason: '$names');
    }
  });

  test('Source does not bypass basic reversal or cloze ordinal checks', () {
    final basicResult = converter.convert(
      note(1, ['front', 'back', 'source']),
      const AnkiModel(
        id: 1,
        name: 'Basic',
        isCloze: false,
        fieldNames: ['Front', 'Back', 'Source'],
      ),
      [card(0), card(1)],
    );
    expect(basicResult.skippedReason, 'unsupportedTemplate');
    final clozeResult = converter.convert(
      note(2, ['{{c1::answer}}', 'source']),
      const AnkiModel(
        id: 2,
        name: 'Cloze',
        isCloze: true,
        fieldNames: ['Text', 'Source'],
      ),
      [card(1)],
    );
    expect(clozeResult.skippedReason, 'unsupportedClozeCards');
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
