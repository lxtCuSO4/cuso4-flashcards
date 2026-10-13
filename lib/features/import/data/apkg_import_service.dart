import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../decks/data/note_repository.dart';
import '../../decks/domain/note.dart';
import '../domain/import_error.dart';
import '../domain/import_report.dart';
import 'anki_collection_reader.dart';
import 'anki_note_converter.dart';
import 'apkg_archive_reader.dart';
import 'media_importer.dart';
import 'media_reference_rewriter.dart';

class ApkgImportService {
  ApkgImportService(
    this.db, {
    ApkgArchiveReader? archiveReader,
    AnkiCollectionReader? collectionReader,
    AnkiNoteConverter? noteConverter,
    this.mediaDirectory,
  }) : _archives = archiveReader ?? ApkgArchiveReader(),
       _collections = collectionReader ?? AnkiCollectionReader(),
       _converter = noteConverter ?? AnkiNoteConverter();

  final AppDatabase db;
  final Directory? mediaDirectory;
  final ApkgArchiveReader _archives;
  final AnkiCollectionReader _collections;
  final AnkiNoteConverter _converter;
  final MediaReferenceRewriter _mediaRewriter = MediaReferenceRewriter();

  Future<ImportReport> importFile(
    File source, {
    bool merge = false,
    bool Function()? isCancelled,
  }) async {
    final package = await _archives.extract(source);
    PreparedMediaImport? prepared;
    var committed = false;
    try {
      final collection = _collections.read(package);
      final modelById = {
        for (final model in collection.models) model.id: model,
      };
      final validDeckIds = collection.decks.map((deck) => deck.id).toSet();
      final cardsByNote = <int, List<AnkiCard>>{};
      for (final card in collection.cards) {
        cardsByNote.putIfAbsent(card.noteId, () => []).add(card);
      }

      final pending = <_PendingNote>[];
      final skippedReasons = <String, int>{};
      final requestedMedia = <String>{};
      void skip(String reason) =>
          skippedReasons.update(reason, (n) => n + 1, ifAbsent: () => 1);
      for (final note in collection.notes) {
        if (!validDeckIds.contains(note.deckId)) {
          skip('missingDeck');
          continue;
        }
        final model = modelById[note.modelId];
        if (model == null) {
          skip('unsupportedTemplate');
          continue;
        }
        final result = _converter.convert(
          note,
          model,
          cardsByNote[note.id] ?? const [],
        );
        if (result.note == null) {
          skip(result.skippedReason ?? 'unsupportedTemplate');
          continue;
        }
        pending.add(_PendingNote(note.deckId, result.note!));
        requestedMedia.addAll(result.note!.mediaNames);
      }

      final destination =
          mediaDirectory ??
          Directory(
            p.join((await getApplicationSupportDirectory()).path, 'media'),
          );
      prepared = await MediaImporter(destination)
          .prepare(package.mediaFiles, requestedMedia);
      final mediaHashes = {
        for (final entry in prepared.assetsByName.entries)
          entry.key: entry.value.contentHash,
      };

      final deckIds = <int, int>{};
      final repository = NoteRepository(db);
      var noteCount = 0;
      var cardCount = 0;
      var mediaCount = 0;
      final mediaReferences = <String, int>{};

      await db.transaction(() async {
        final createdPaths = <String, int>{};
        final rootNames = (await db.select(db.decks).get())
            .where((deck) => deck.parentId == null)
            .map((deck) => deck.name)
            .toSet();

        Future<int> ensurePath(String fullName) async {
          final segments = fullName
              .split('::')
              .map((part) => part.trim())
              .toList();
          if (segments.any((part) => part.isEmpty || part.length > 255)) {
            throw FormatException('牌组名称无效：$fullName');
          }
          int? parentId;
          for (var i = 0; i < segments.length; i++) {
            final key = segments.take(i + 1).join('::');
            final cached = createdPaths[key];
            if (cached != null) {
              parentId = cached;
              continue;
            }
            var name = segments[i];
            if (parentId == null && !merge) {
              name = _copyName(name, rootNames);
              rootNames.add(name);
            } else if (merge) {
              final currentParent = parentId;
              final existing =
                  await (db.select(db.decks)..where(
                        (deck) => currentParent == null
                            ? deck.parentId.isNull() & deck.name.equals(name)
                            : deck.parentId.equals(currentParent) &
                                  deck.name.equals(name),
                      ))
                      .get();
              if (existing.isNotEmpty) {
                parentId = existing.first.id;
                createdPaths[key] = parentId;
                continue;
              }
            }
            final now = DateTime.now().toUtc().millisecondsSinceEpoch;
            parentId = await db
                .into(db.decks)
                .insert(
                  DecksCompanion.insert(
                    name: name,
                    parentId: Value(parentId),
                    createdAtUtc: now,
                    modifiedAtUtc: now,
                  ),
                );
            createdPaths[key] = parentId;
          }
          return parentId!;
        }

        for (final deck in collection.decks) {
          deckIds[deck.id] = await ensurePath(deck.name);
        }
        for (final entry in pending) {
          if (isCancelled?.call() ?? false) {
            throw const ApkgImportException(
              ImportErrorCode.cancelled,
              '已取消导入，本次内容未保存。',
            );
          }
          final targetDeck = deckIds[entry.sourceDeckId]!;
          final converted = entry.note;
          final fields = converted.fields.map(
            (key, value) =>
                MapEntry(key, _mediaRewriter.rewrite(value, mediaHashes)),
          );
          final id = converted.type == NoteType.basic
              ? await repository.createBasicNote(
                  deckId: targetDeck,
                  front: fields['front']!,
                  back: fields['back']!,
                  tags: converted.tags,
                )
              : await repository.createClozeNote(
                  deckId: targetDeck,
                  text: fields['text']!,
                  extra: fields['extra']!,
                  tags: converted.tags,
                );
          noteCount++;
          cardCount += (await (db.select(
            db.cards,
          )..where((card) => card.noteId.equals(id))).get()).length;
          final hashes = converted.mediaNames
              .map((name) => prepared!.assetsByName[name]?.contentHash)
              .whereType<String>()
              .toSet();
          for (final hash in hashes) {
            mediaReferences.update(hash, (n) => n + 1, ifAbsent: () => 1);
          }
        }

        if (isCancelled?.call() ?? false) {
          throw const ApkgImportException(
            ImportErrorCode.cancelled,
            '已取消导入，本次内容未保存。',
          );
        }
        mediaCount = await prepared!.commit();
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        for (final asset in prepared!.assetsByName.values) {
          final count = mediaReferences.remove(asset.contentHash);
          if (count == null) continue;
          final existing =
              await (db.select(db.media)
                    ..where((row) => row.contentHash.equals(asset.contentHash)))
                  .getSingleOrNull();
          if (existing == null) {
            await db
                .into(db.media)
                .insert(
                  MediaCompanion.insert(
                    contentHash: asset.contentHash,
                    originalName: asset.originalName,
                    relativePath: asset.relativePath,
                    mimeType: asset.mimeType,
                    byteLength: asset.byteLength,
                    referenceCount: Value(count),
                    createdAtUtc: now,
                  ),
                );
          } else {
            await (db.update(
              db.media,
            )..where((row) => row.id.equals(existing.id))).write(
              MediaCompanion(
                referenceCount: Value(existing.referenceCount + count),
              ),
            );
          }
        }
      });
      committed = true;
      return ImportReport(
        decks: deckIds.length,
        notes: noteCount,
        cards: cardCount,
        media: mediaCount,
        skipped: skippedReasons.values.fold(0, (sum, n) => sum + n),
        skippedReasons: Map.unmodifiable(skippedReasons),
        missingMedia: prepared.missingNames.length,
        unsupportedMedia: prepared.unsupportedNames.length,
      );
    } catch (error) {
      if (!committed && prepared != null) await prepared.rollback();
      if (error is ApkgImportException) rethrow;
      throw ApkgImportException(
        ImportErrorCode.transactionFailed,
        '导入失败，已回滚本次导入：$error',
      );
    } finally {
      if (committed && prepared != null) {
        try {
          await prepared.complete();
        } on FileSystemException {
          // A leftover staging directory does not invalidate committed data.
        }
      }
      await package.dispose();
    }
  }

  String _copyName(String name, Set<String> existing) {
    if (!existing.contains(name)) return name;
    final first = '$name (导入)';
    if (!existing.contains(first)) return first;
    var suffix = 2;
    while (existing.contains('$name (导入 $suffix)')) {
      suffix++;
    }
    return '$name (导入 $suffix)';
  }
}

class _PendingNote {
  const _PendingNote(this.sourceDeckId, this.note);
  final int sourceDeckId;
  final ConvertedAnkiNote note;
}
