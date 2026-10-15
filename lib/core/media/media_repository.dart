import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../database/app_database.dart';
import 'prepared_image.dart';

enum MediaKind { image, audio }

class LocalMedia {
  const LocalMedia({required this.file, required this.mimeType});
  final File file;
  final String mimeType;
}

/// Counts each local asset once per note, regardless of repeated occurrences.
class MediaRepository {
  MediaRepository(this.db, {this.directory});
  final AppDatabase db;
  final Directory? directory;
  static final _hash = RegExp(r'^media:([a-f0-9]{64})$');
  static final _sound = RegExp(r'\[sound:media:([a-f0-9]{64})\]');

  /// Keeps image rows and note references in one transaction, excluding GC.
  Future<T> saveImages<T>(
    Iterable<PreparedImage> images,
    Map<String, String> fields,
    Future<T> Function() save,
  ) {
    final used = references(fields);
    final selected = {
      for (final image in images)
        if (used.contains(image.hash)) image.hash: image,
    };
    if (selected.isEmpty) return save();
    return db.transaction(() async {
      final root =
          directory ??
          Directory(
            p.join((await getApplicationSupportDirectory()).path, 'media'),
          );
      await root.create(recursive: true);
      final canonicalRoot = await root.resolveSymbolicLinks();
      final created = <File>[];
      try {
        for (final image in selected.values) {
          final file = File(p.join(canonicalRoot, image.hash));
          final type = await FileSystemEntity.type(
            file.path,
            followLinks: false,
          );
          if (type == FileSystemEntityType.notFound) {
            // A killed app can leave a complete orphan, never a partial hash file.
            final staging = await root.createTemp('.editor-');
            try {
              final staged = File(p.join(staging.path, image.hash));
              await staged.writeAsBytes(image.bytes, flush: true);
              await staged.rename(file.path);
              created.add(file);
            } finally {
              await staging.delete(recursive: true);
            }
          } else if (type != FileSystemEntityType.file ||
              p.dirname(await file.resolveSymbolicLinks()) != canonicalRoot ||
              (await sha256.bind(file.openRead()).first).toString() !=
                  image.hash) {
            throw StateError('本地图片文件异常，请重试或恢复备份。');
          }
          final existing = await (db.select(
            db.media,
          )..where((m) => m.contentHash.equals(image.hash))).getSingleOrNull();
          if (existing == null) {
            await db
                .into(db.media)
                .insert(
                  MediaCompanion.insert(
                    contentHash: image.hash,
                    originalName: image.name,
                    relativePath: image.hash,
                    mimeType: image.mimeType,
                    byteLength: image.bytes.length,
                    createdAtUtc: DateTime.now().toUtc().millisecondsSinceEpoch,
                  ),
                );
          } else if (existing.relativePath != image.hash ||
              existing.mimeType != image.mimeType ||
              existing.byteLength != image.bytes.length) {
            throw StateError('本地图片记录异常，请重试或恢复备份。');
          }
        }
        return await save();
      } catch (_) {
        for (final file in created) {
          try {
            if (await file.exists()) await file.delete();
          } on FileSystemException {
            /* Retry save can reuse the hash file. */
          }
        }
        rethrow;
      }
    });
  }

  /// Never turns arbitrary card URLs or filenames into filesystem access.
  Future<LocalMedia?> resolve(String token, {required MediaKind kind}) async {
    final match = _hash.firstMatch(token);
    if (match == null) return null;
    final hash = match[1]!;
    final asset = await (db.select(
      db.media,
    )..where((m) => m.contentHash.equals(hash))).getSingleOrNull();
    if (asset == null || asset.relativePath != hash) return null;
    final allowed = kind == MediaKind.image
        ? {'image/png', 'image/jpeg', 'image/gif', 'image/webp'}
        : {'audio/mpeg', 'audio/wav', 'audio/ogg', 'audio/mp4'};
    if (!allowed.contains(asset.mimeType)) return null;
    try {
      final root =
          directory ??
          Directory(
            p.join((await getApplicationSupportDirectory()).path, 'media'),
          );
      final canonicalRoot = await root.resolveSymbolicLinks();
      final file = File(p.join(canonicalRoot, hash));
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        return null;
      }
      if (p.dirname(await file.resolveSymbolicLinks()) != canonicalRoot ||
          await file.length() != asset.byteLength) {
        return null;
      }
      return LocalMedia(file: file, mimeType: asset.mimeType);
    } on FileSystemException {
      return null;
    }
  }

  Set<String> references(Map<String, String> fields) {
    final result = <String>{};
    for (final value in fields.values) {
      final fragment = html.parseFragment(value);
      for (final image in fragment.querySelectorAll('img')) {
        final match = _hash.firstMatch(image.attributes['src'] ?? '');
        if (match != null) result.add(match[1]!);
      }
      for (final match in _sound.allMatches(fragment.text ?? '')) {
        result.add(match[1]!);
      }
    }
    return result;
  }

  Map<String, String> fieldsFromJson(String value) =>
      Map<String, String>.from(jsonDecode(value) as Map);

  /// The caller owns the note/deck transaction. No files are removed here.
  Future<void> replaceReferences(
    Map<String, String> before,
    Map<String, String> after,
  ) async {
    final oldHashes = references(before);
    final newHashes = references(after);
    for (final hash in oldHashes.difference(newHashes)) {
      await db.customUpdate(
        'UPDATE media SET reference_count = MAX(0, reference_count - 1) WHERE content_hash = ?',
        variables: [Variable(hash)],
        updates: {db.media},
      );
    }
    for (final hash in newHashes.difference(oldHashes)) {
      await db.customUpdate(
        'UPDATE media SET reference_count = reference_count + 1 WHERE content_hash = ?',
        variables: [Variable(hash)],
        updates: {db.media},
      );
    }
  }

  /// Rechecks actual notes while holding the database transaction, so stale
  /// counters cannot remove shared media or race a new note/import commit.
  Future<void> collectUnused() async {
    final root =
        directory ??
        Directory(
          p.join((await getApplicationSupportDirectory()).path, 'media'),
        );
    if (!await root.exists()) return;
    final canonicalRoot = await root.resolveSymbolicLinks();
    await db.transaction(() async {
      final candidates = await (db.select(
        db.media,
      )..where((m) => m.referenceCount.equals(0))).get();
      if (candidates.isEmpty) return;
      final used = <String>{};
      for (final note in await db.select(db.notes).get()) {
        used.addAll(references(fieldsFromJson(note.fieldsJson)));
      }
      for (final asset in candidates) {
        if (used.contains(asset.contentHash)) continue;
        // Only content-addressed files directly inside the private directory.
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(asset.relativePath) ||
            asset.relativePath != asset.contentHash) {
          continue;
        }
        final file = File(p.join(canonicalRoot, asset.relativePath));
        final type = await FileSystemEntity.type(file.path, followLinks: false);
        if (type == FileSystemEntityType.link ||
            type == FileSystemEntityType.directory) {
          continue;
        }
        if (type == FileSystemEntityType.file) {
          final target = await file.resolveSymbolicLinks();
          if (p.dirname(target) != canonicalRoot) continue;
          try {
            await file.delete();
          } on FileSystemException {
            continue; // Retry later; note saves remain successful.
          }
        }
        await (db.delete(db.media)..where((m) => m.id.equals(asset.id))).go();
      }
    });
  }
}
