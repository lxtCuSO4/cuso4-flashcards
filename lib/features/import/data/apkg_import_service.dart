import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/database/app_database.dart';
import '../../decks/data/note_repository.dart';
import '../../decks/domain/note.dart';
import '../domain/import_error.dart';
import '../domain/import_report.dart';
import '../domain/import_progress.dart';
import 'apkg_background_reader.dart';
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
  bool _busy = false;

  Future<ImportReport> importFile(
    File source, {
    bool merge = false,
    bool Function()? isCancelled,
    void Function(ImportProgress)? onProgress,
  }) async {
    if (_busy) throw StateError('已有导入任务正在进行');
    _busy = true;
    int? jobId;
    try {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      jobId = await db
          .into(db.importJobs)
          .insert(
            ImportJobsCompanion.insert(
              sourceName: p.basename(source.path),
              status: 'running',
              createdAtUtc: now,
              modifiedAtUtc: now,
            ),
          );
      return await _import(source, jobId, merge, isCancelled, onProgress);
    } catch (error) {
      if (jobId != null) {
        await (db.update(
          db.importJobs,
        )..where((j) => j.id.equals(jobId!))).write(
          ImportJobsCompanion(
            status: Value(
              error is ApkgImportException &&
                      error.code == ImportErrorCode.cancelled
                  ? 'cancelled'
                  : 'failed',
            ),
            modifiedAtUtc: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
          ),
        );
      }
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<ImportReport> _import(
    File source,
    int jobId,
    bool merge,
    bool Function()? isCancelled,
    void Function(ImportProgress)? onProgress,
  ) async {
    void checkCancellation() {
      if (isCancelled?.call() ?? false) {
        throw const ApkgImportException(
          ImportErrorCode.cancelled,
          '已取消导入，本次内容未保存。',
        );
      }
    }

    final destination =
        mediaDirectory ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'media'),
        );
    final temporary = Directory(p.join(destination.path, '.imports'));
    checkCancellation();
    onProgress?.call(const ImportProgress(ImportPhase.extracting));
    final package = await extractInBackground(
      _archives,
      source.path,
      temporary.path,
    );
    PreparedMediaImport? prepared;
    var committed = false;
    try {
      checkCancellation();
      onProgress?.call(const ImportProgress(ImportPhase.reading));
      checkCancellation();
      final collection = await readInBackground(
        _collections,
        _converter,
        package,
      );
      checkCancellation();
      final pending = collection.notes;
      final skippedReasons = collection.skippedReasons;
      onProgress?.call(
        ImportProgress(
          ImportPhase.media,
          total: collection.requestedMedia.length,
        ),
      );
      prepared = await MediaImporter(destination).prepare(
        package.mediaFiles,
        collection.requestedMedia,
        isCancelled: isCancelled,
        onProgress: (count) => onProgress?.call(
          ImportProgress(
            ImportPhase.media,
            completed: count,
            total: collection.requestedMedia.length,
          ),
        ),
      );
      checkCancellation();
      final mediaHashes = {
        for (final entry in prepared.assetsByName.entries)
          entry.key: entry.value.contentHash,
      };

      final deckIds = <int, int>{};
      final repository = NoteRepository(db);
      var noteCount = 0;
      var cardCount = 0;
      var mediaCount = 0;

      ImportReport? report;
      onProgress?.call(
        ImportProgress(ImportPhase.saving, total: pending.length),
      );
      await db.transaction(() async {
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        for (final asset in prepared!.assetsByName.values) {
          await db
              .into(db.media)
              .insert(
                MediaCompanion.insert(
                  contentHash: asset.contentHash,
                  originalName: asset.originalName,
                  relativePath: asset.relativePath,
                  mimeType: asset.mimeType,
                  byteLength: asset.byteLength,
                  createdAtUtc: now,
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
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
          checkCancellation();
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
          if (noteCount == 1 ||
              noteCount % 100 == 0 ||
              noteCount == pending.length) {
            onProgress?.call(
              ImportProgress(
                ImportPhase.saving,
                completed: noteCount,
                total: pending.length,
              ),
            );
            await Future<void>.delayed(Duration.zero);
          }
        }

        checkCancellation();
        mediaCount = await prepared!.commit();
        checkCancellation();
        report = ImportReport(
          decks: deckIds.length,
          notes: noteCount,
          cards: cardCount,
          media: mediaCount,
          skipped: skippedReasons.values.fold(0, (sum, n) => sum + n),
          skippedReasons: Map.unmodifiable(skippedReasons),
          missingMedia: prepared!.missingNames.length,
          unsupportedMedia: prepared.unsupportedNames.length,
        );
        await (db.update(
          db.importJobs,
        )..where((j) => j.id.equals(jobId))).write(
          ImportJobsCompanion(
            status: const Value('completed'),
            reportJson: Value(jsonEncode(report!.toJson())),
            modifiedAtUtc: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
          ),
        );
        for (final entry in skippedReasons.entries) {
          await db
              .into(db.importJobErrors)
              .insert(
                ImportJobErrorsCompanion.insert(
                  jobId: jobId,
                  reason: entry.key,
                  count: entry.value,
                ),
              );
        }
      });
      committed = true;
      return report!;
    } catch (error) {
      if (!committed && prepared != null) await prepared.rollback();
      if (error is ApkgImportException) rethrow;
      throw ApkgImportException(
        ImportErrorCode.transactionFailed,
        '导入失败，已回滚本次导入。请检查牌组内容与可用存储空间后重试。',
      );
    } finally {
      if (committed && prepared != null) {
        try {
          await prepared.complete();
        } on FileSystemException {
          // A leftover staging directory does not invalidate committed data.
        }
      }
      try {
        await package.dispose();
      } on FileSystemException {
        // Cleanup failure must not misreport a successfully committed import.
      }
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
