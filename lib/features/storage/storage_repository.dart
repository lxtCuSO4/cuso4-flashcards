import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/database/app_database.dart';
import '../../core/media/media_repository.dart';

class StorageSummary {
  const StorageSummary({
    required this.databaseBytes,
    required this.mediaBytes,
    required this.unusedBytes,
    required this.unusedCount,
    required this.missingCount,
  });
  final int databaseBytes, mediaBytes, unusedBytes, unusedCount, missingCount;
}

class StorageCleanup {
  const StorageCleanup(this.files, this.bytes, this.failed);
  final int files, bytes, failed;
}

class StorageRepository {
  StorageRepository(this.db, this.media, {this.root});
  final AppDatabase db;
  final MediaRepository media;
  final Directory? root;
  static final _hash = RegExp(r'^[a-f0-9]{64}$');

  Future<({Directory root, Directory folder})> _paths() async {
    final support = root ?? await getApplicationSupportDirectory();
    return (
      root: support,
      folder: media.directory ?? Directory(p.join(support.path, 'media')),
    );
  }

  Future<Set<String>> _used() async {
    final used = <String>{};
    for (final note in await db.select(db.notes).get()) {
      used.addAll(media.references(media.fieldsFromJson(note.fieldsJson)));
    }
    return used;
  }

  Future<StorageSummary> inspect() => db.transaction(() async {
    final paths = await _paths();
    final used = await _used();
    final rows = {
      for (final row in await db.select(db.media).get()) row.contentHash: row,
    };
    final files = await _files(paths.folder);
    var databaseBytes = 0,
        mediaBytes = 0,
        unusedBytes = 0,
        unusedCount = 0,
        missing = 0;
    for (final suffix in ['', '-wal', '-shm']) {
      final file = File(p.join(paths.root.path, 'cuso4.sqlite$suffix'));
      if (await file.exists()) databaseBytes += await file.length();
    }
    for (final entry in files.entries) {
      final row = rows[entry.key];
      final length = await entry.value.length();
      mediaBytes += length;
      if (!used.contains(entry.key) &&
          (row == null || row.relativePath == entry.key)) {
        unusedCount++;
        unusedBytes += length;
      }
    }
    for (final hash in used) {
      final row = rows[hash];
      final file = files[hash];
      if (row == null ||
          row.relativePath != hash ||
          file == null ||
          await file.length() != row.byteLength) {
        missing++;
      }
    }
    return StorageSummary(
      databaseBytes: databaseBytes,
      mediaBytes: mediaBytes,
      unusedBytes: unusedBytes,
      unusedCount: unusedCount,
      missingCount: missing,
    );
  });

  Future<Map<String, File>> _files(Directory folder) async {
    if (!await folder.exists()) return {};
    final canonical = await folder.resolveSymbolicLinks();
    final files = <String, File>{};
    await for (final entry in folder.list(followLinks: false)) {
      if (entry is File &&
          _hash.hasMatch(p.basename(entry.path)) &&
          p.dirname(await entry.resolveSymbolicLinks()) == canonical) {
        files[p.basename(entry.path)] = entry;
      }
    }
    return files;
  }

  /// Rechecks the current notes under the same DB lock as import/editor commits.
  Future<StorageCleanup> clean() => db.transaction(() async {
    final used = await _used();
    final rows = {
      for (final row in await db.select(db.media).get()) row.contentHash: row,
    };
    final paths = await _paths();
    final files = await _files(paths.folder);
    var count = 0, bytes = 0, failed = 0;
    for (final entry in files.entries) {
      final row = rows[entry.key];
      if (used.contains(entry.key) ||
          row != null && row.relativePath != entry.key) {
        continue;
      }
      try {
        final length = await entry.value.length();
        await entry.value.delete();
        count++;
        bytes += length;
      } on FileSystemException {
        failed++;
        continue;
      }
      if (row != null) {
        await (db.delete(db.media)..where((m) => m.id.equals(row.id))).go();
      }
    }
    // Unreferenced metadata whose file is already absent is safe to remove too.
    for (final row in rows.values) {
      if (!used.contains(row.contentHash) &&
          row.relativePath == row.contentHash &&
          _hash.hasMatch(row.contentHash) &&
          !files.containsKey(row.contentHash) &&
          await FileSystemEntity.type(
                p.join(paths.folder.path, row.contentHash),
                followLinks: false,
              ) ==
              FileSystemEntityType.notFound) {
        await (db.delete(db.media)..where((m) => m.id.equals(row.id))).go();
      }
    }
    return StorageCleanup(count, bytes, failed);
  });
}
