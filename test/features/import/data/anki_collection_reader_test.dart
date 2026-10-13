import 'dart:convert';
import 'dart:io';

import 'package:cuso4_flashcards/features/import/data/anki_collection_reader.dart';
import 'package:cuso4_flashcards/features/import/data/apkg_archive_reader.dart';
import 'package:cuso4_flashcards/features/import/domain/import_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  late Directory scratch;
  late File collectionFile;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('anki_collection_test_');
    collectionFile = File(
      '${scratch.path}${Platform.pathSeparator}collection.anki2',
    );
  });
  tearDown(() async => scratch.delete(recursive: true));

  ApkgPackage package() => ApkgPackage(
    root: scratch,
    collectionPath: collectionFile,
    mediaFiles: const {},
    temporary: false,
  );

  test(
    'reads nested decks, model fields, note fields, tags and card ordinals',
    () {
      final db = sqlite3.open(collectionFile.path);
      try {
        db.execute(
          'CREATE TABLE col (decks TEXT NOT NULL, models TEXT NOT NULL)',
        );
        db.execute(
          'CREATE TABLE notes (id INTEGER, mid INTEGER, flds TEXT, tags TEXT)',
        );
        db.execute(
          'CREATE TABLE cards (id INTEGER, nid INTEGER, did INTEGER, ord INTEGER)',
        );
        db.execute('INSERT INTO col VALUES (?, ?)', [
          jsonEncode({
            '1': {'name': 'Default'},
            '2': {'name': 'Languages::Japanese'},
          }),
          jsonEncode({
            '100': {
              'name': 'Basic',
              'type': 0,
              'flds': [
                {'name': 'Front', 'ord': 0},
                {'name': 'Back', 'ord': 1},
              ],
            },
            '101': {
              'name': 'Cloze',
              'type': 1,
              'flds': [
                {'name': 'Text', 'ord': 0},
                {'name': 'Extra', 'ord': 1},
              ],
            },
          }),
        ]);
        db.execute('INSERT INTO notes VALUES (?, ?, ?, ?)', [
          10,
          100,
          'question\u001fanswer',
          ' lang  common ',
        ]);
        db.execute('INSERT INTO notes VALUES (?, ?, ?, ?)', [
          11,
          101,
          '{{c1::answer}}\u001fextra',
          ' cloze ',
        ]);
        db.execute('INSERT INTO cards VALUES (?, ?, ?, ?)', [20, 10, 2, 0]);
        db.execute('INSERT INTO cards VALUES (?, ?, ?, ?)', [21, 11, 2, 0]);
      } finally {
        db.close();
      }

      final result = AnkiCollectionReader().read(package());
      expect(
        result.decks.singleWhere((d) => d.id == 2).name,
        'Languages::Japanese',
      );
      expect(result.models.singleWhere((m) => m.id == 100).fieldNames, [
        'Front',
        'Back',
      ]);
      expect(result.notes.singleWhere((n) => n.id == 10).fields, [
        'question',
        'answer',
      ]);
      expect(result.notes.singleWhere((n) => n.id == 10).tags, [
        'lang',
        'common',
      ]);
      expect(result.notes.singleWhere((n) => n.id == 11).isCloze, isTrue);
      expect(result.cards.map((c) => c.ordinal), [0, 0]);
      expect(result.notes.every((n) => n.deckId == 2), isTrue);
    },
  );

  test('rejects collections without the supported metadata schema', () {
    final db = sqlite3.open(collectionFile.path);
    db.execute('CREATE TABLE col (id INTEGER)');
    db.close();
    expect(
      () => AnkiCollectionReader().read(package()),
      throwsA(
        isA<ApkgImportException>().having(
          (e) => e.code,
          'code',
          ImportErrorCode.unsupportedCollectionVersion,
        ),
      ),
    );
  });
}
