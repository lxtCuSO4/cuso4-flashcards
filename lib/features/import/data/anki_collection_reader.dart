import 'dart:convert';

import 'package:sqlite3/sqlite3.dart';

import '../domain/import_error.dart';
import 'anki_protobuf.dart';
import 'apkg_archive_reader.dart';

class AnkiDeck {
  const AnkiDeck(this.id, this.name);
  final int id;
  final String name;
}

class AnkiModel {
  const AnkiModel({
    required this.id,
    required this.name,
    required this.isCloze,
    required this.fieldNames,
  });
  final int id;
  final String name;
  final bool isCloze;
  final List<String> fieldNames;
}

class AnkiCard {
  const AnkiCard({
    required this.id,
    required this.noteId,
    required this.deckId,
    required this.ordinal,
  });
  final int id;
  final int noteId;
  final int deckId;
  final int ordinal;
}

class AnkiNote {
  const AnkiNote({
    required this.id,
    required this.modelId,
    required this.deckId,
    required this.isCloze,
    required this.fields,
    required this.tags,
  });
  final int id;
  final int modelId;
  final int deckId;
  final bool isCloze;
  final List<String> fields;
  final List<String> tags;
}

class AnkiCollection {
  const AnkiCollection({
    required this.decks,
    required this.models,
    required this.notes,
    required this.cards,
  });
  final List<AnkiDeck> decks;
  final List<AnkiModel> models;
  final List<AnkiNote> notes;
  final List<AnkiCard> cards;
}

class AnkiCollectionReader {
  AnkiCollection read(ApkgPackage package) {
    final db = sqlite3.open(
      package.collectionPath.path,
      mode: OpenMode.readOnly,
    );
    try {
      // Anki's WITHOUT ROWID tables require this named collation even for
      // scans ordered by numeric IDs/ordinals. We never compare text columns
      // or write Anki data, so their locale/case ordering is immaterial here.
      db.createCollation(
        name: 'unicase',
        function: (a, b) => (a ?? '').compareTo(b ?? ''),
      );
      final col = db.select('SELECT * FROM col LIMIT 1');
      if (col.isEmpty) {
        throw const ApkgImportException(
          ImportErrorCode.unsupportedCollectionVersion,
          '找不到受支持的 Anki 集合表。',
        );
      }
      final normalized =
          db
              .select(
                "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('notetypes','fields','decks')",
              )
              .length ==
          3;
      final List<AnkiModel> parsedModels;
      final List<AnkiDeck> decks;
      if (normalized) {
        final version = col.first['ver'] as int;
        if (version < 15 || version > 18) {
          throw const FormatException('Unsupported schema');
        }
        final fields = <int, List<String>>{};
        for (final row in db.select(
          'SELECT ntid, ord, name FROM fields ORDER BY ntid, ord',
        )) {
          final names = fields.putIfAbsent(row['ntid'] as int, () => []);
          if (row['ord'] != names.length) {
            throw const FormatException('Invalid field order');
          }
          names.add(row['name'] as String);
        }
        parsedModels = db
            .select('SELECT id, name, config FROM notetypes ORDER BY id')
            .map((row) {
              var kind = 0;
              for (final field in readAnkiProto(row['config'] as List<int>)) {
                if (field.number == 1) {
                  if (field.wire != 0) throw const FormatException();
                  kind = field.integer!;
                }
              }
              if (kind != 0 && kind != 1) {
                throw const FormatException('Unknown note kind');
              }
              return AnkiModel(
                id: row['id'] as int,
                name: row['name'] as String,
                isCloze: kind == 1,
                fieldNames: fields[row['id']] ?? [],
              );
            })
            .toList();
        decks = db
            .select('SELECT id, name FROM decks ORDER BY id')
            .map(
              (row) => AnkiDeck(
                row['id'] as int,
                (row['name'] as String).replaceAll('\u001f', '::'),
              ),
            )
            .toList();
      } else {
        final decksJson =
            jsonDecode(col.first['decks'] as String) as Map<String, dynamic>;
        final models =
            jsonDecode(col.first['models'] as String) as Map<String, dynamic>;
        parsedModels = models.entries.map((entry) {
          final value = entry.value as Map<String, dynamic>;
          final fields =
              (value['flds'] as List<dynamic>)
                  .cast<Map<String, dynamic>>()
                  .toList()
                ..sort((a, b) => (a['ord'] as int).compareTo(b['ord'] as int));
          return AnkiModel(
            id: int.parse(entry.key),
            name: value['name'] as String,
            isCloze: value['type'] == 1,
            fieldNames: fields.map((field) => field['name'] as String).toList(),
          );
        }).toList();
        decks = decksJson.entries
            .map(
              (e) => AnkiDeck(
                int.parse(e.key),
                (e.value as Map)['name'] as String,
              ),
            )
            .toList();
      }
      final modelById = {for (final model in parsedModels) model.id: model};
      final cards = db
          .select('SELECT id, nid, did, ord FROM cards ORDER BY nid, ord')
          .map(
            (row) => AnkiCard(
              id: row['id'] as int,
              noteId: row['nid'] as int,
              deckId: row['did'] as int,
              ordinal: row['ord'] as int,
            ),
          )
          .toList();
      final deckByNote = <int, int>{};
      for (final card in cards) {
        deckByNote.putIfAbsent(card.noteId, () => card.deckId);
      }
      final notes = <AnkiNote>[];
      for (final row in db.select('SELECT id, mid, flds, tags FROM notes')) {
        final model = modelById[row['mid']];
        notes.add(
          AnkiNote(
            id: row['id'] as int,
            modelId: row['mid'] as int,
            deckId: deckByNote[row['id']] ?? 0,
            isCloze: model?.isCloze ?? false,
            fields: (row['flds'] as String).split('\u001f'),
            tags: (row['tags'] as String)
                .trim()
                .split(RegExp(r'\s+'))
                .where((e) => e.isNotEmpty)
                .toList(),
          ),
        );
      }
      return AnkiCollection(
        decks: decks,
        models: parsedModels,
        notes: notes,
        cards: cards,
      );
    } on ApkgImportException {
      rethrow;
    } catch (_) {
      throw const ApkgImportException(
        ImportErrorCode.unsupportedCollectionVersion,
        '无法读取该 Anki 集合数据库。',
      );
    } finally {
      db.close();
    }
  }
}
