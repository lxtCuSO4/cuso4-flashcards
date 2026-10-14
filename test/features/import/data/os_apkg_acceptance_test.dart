import 'dart:convert';
import 'dart:io';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/import/data/apkg_import_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  // Optional read-only acceptance input; never commit the user's deck contents.
  final packagePath = Platform.environment['CUSO4_OS_APKG'];
  test(
    'imports the supplied OS package: 520 notes and 670 new cards',
    () async {
      final scratch = await Directory.systemTemp.createTemp('os_acceptance_');
      final db = AppDatabase(NativeDatabase.memory());
      try {
        final report = await ApkgImportService(
          db,
          mediaDirectory: Directory(p.join(scratch.path, 'media')),
        ).importFile(File(packagePath!));
        expect((report.notes, report.cards, report.media), (520, 670, 0));
        expect(report.skipped, 0);
        expect(report.skippedReasons, isEmpty);
        expect(report.missingMedia, 0);
        final notes = await db.select(db.notes).get();
        expect(notes.where((note) => note.noteType == 0).length, 310);
        expect(notes.where((note) => note.noteType == 1).length, 210);
        for (final note in notes) {
          final fields = jsonDecode(note.fieldsJson) as Map;
          final answer =
              fields[note.noteType == 0 ? 'back' : 'extra'] as String;
          expect(answer, contains('来源：'), reason: 'note ${note.id}');
        }
        final cards = await db.select(db.cards).get();
        expect(
          cards.every(
            (card) =>
                card.state == 0 &&
                card.repetitions == 0 &&
                card.lastReviewAtUtc == null,
          ),
          isTrue,
        );
      } finally {
        await db.close();
        await scratch.delete(recursive: true);
      }
    },
    skip: packagePath == null ? 'Set CUSO4_OS_APKG for the local deck' : false,
  );
}
