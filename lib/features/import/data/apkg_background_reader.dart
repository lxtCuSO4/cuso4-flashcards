import 'dart:io';
import 'dart:isolate';

import 'anki_collection_reader.dart';
import 'anki_note_converter.dart';
import 'apkg_archive_reader.dart';

class PendingAnkiNote {
  const PendingAnkiNote(this.sourceDeckId, this.note);
  final int sourceDeckId;
  final ConvertedAnkiNote note;
}

class ParsedAnkiCollection {
  const ParsedAnkiCollection(
    this.decks,
    this.notes,
    this.skippedReasons,
    this.requestedMedia,
  );
  final List<AnkiDeck> decks;
  final List<PendingAnkiNote> notes;
  final Map<String, int> skippedReasons;
  final Set<String> requestedMedia;
}

// Keep isolate closures separate from the service: never capture the live DB.
Future<ApkgPackage> extractInBackground(
  ApkgArchiveReader reader,
  String path,
  String destination,
) => Isolate.run(
  () => reader.extract(File(path), destination: Directory(destination)),
);

Future<ParsedAnkiCollection> readInBackground(
  AnkiCollectionReader reader,
  AnkiNoteConverter converter,
  ApkgPackage package,
) => Isolate.run(() {
  final collection = reader.read(package);
  final models = {for (final model in collection.models) model.id: model};
  final validDecks = collection.decks.map((deck) => deck.id).toSet();
  final cardsByNote = <int, List<AnkiCard>>{};
  for (final card in collection.cards) {
    cardsByNote.putIfAbsent(card.noteId, () => []).add(card);
  }
  final notes = <PendingAnkiNote>[];
  final skipped = <String, int>{};
  final media = <String>{};
  void skip(String reason) =>
      skipped.update(reason, (n) => n + 1, ifAbsent: () => 1);
  for (final note in collection.notes) {
    final model = models[note.modelId];
    if (model == null) {
      skip('unsupportedTemplate');
    } else if (!validDecks.contains(note.deckId)) {
      skip('missingDeck');
    } else {
      final result = converter.convert(
        note,
        model,
        cardsByNote[note.id] ?? const [],
      );
      if (result.note == null) {
        skip(result.skippedReason ?? 'unsupportedTemplate');
      } else {
        notes.add(PendingAnkiNote(note.deckId, result.note!));
        media.addAll(result.note!.mediaNames);
      }
    }
  }
  return ParsedAnkiCollection(collection.decks, notes, skipped, media);
});
