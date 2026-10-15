import 'dart:convert';
import 'dart:io';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_question.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/import/data/apkg_import_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final path = Platform.environment['LUNAR_DB_APKG'];
  test(
    'real DB package imports 67 single and 17 multiple choices with answers and sources',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'db_choice_acceptance_',
      );
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final report = await ApkgImportService(
          db,
          mediaDirectory: Directory('${root.path}/media'),
        ).importFile(File(path!));
        expect((report.notes, report.cards, report.skipped), (84, 84, 0));
        expect(
          (report.singleChoice, report.multipleChoice, report.choiceFallback),
          (67, 17, 0),
        );
        final notes = await db.select(db.notes).get();
        expect(
          notes.where((n) => n.noteType == NoteType.singleChoice.index).length,
          67,
        );
        expect(
          notes
              .where((n) => n.noteType == NoteType.multipleChoice.index)
              .length,
          17,
        );
        for (final note in notes) {
          final question = ChoiceQuestion.fromFields(
            NoteType.values[note.noteType],
            Map<String, String>.from(jsonDecode(note.fieldsJson) as Map),
          );
          expect(question.options.length, 4);
          expect(question.explanation, allOf(contains('解析'), contains('来源：')));
        }
        expect(
          (await db.select(db.cards).get()).every(
            (c) => c.repetitions == 0 && c.lastReviewAtUtc == null,
          ),
          isTrue,
        );
      } finally {
        await db.close();
        await root.delete(recursive: true);
      }
    },
    skip: path == null
        ? 'Set LUNAR_DB_APKG for local read-only acceptance'
        : false,
  );
}
