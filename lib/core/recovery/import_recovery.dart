import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../features/import/domain/import_recovery_notice.dart';
import '../media/media_references.dart';

/// Startup only, before repositories can begin another import. Runs on the
/// database isolate; never scans a directory belonging to a live import.
class ImportRecovery {
  ImportRecovery(this.root);
  final Directory root;
  static final _stageName = RegExp(r'^(job_|cuso4_apkg_)[a-zA-Z0-9]+$');
  static final _hash = RegExp(r'^[a-f0-9]{64}$');

  void run(Database database) {
    if (database.select('PRAGMA user_version').single.values.single != 1) {
      return;
    }
    database.execute('BEGIN IMMEDIATE');
    try {
      final jobs =
          database
                  .select(
                    "SELECT COUNT(*) AS count FROM import_jobs WHERE status = 'running'",
                  )
                  .single['count']
              as int;
      final now = DateTime.now().toUtc().millisecondsSinceEpoch;
      final failures = _clean(database);
      database.execute(
        "UPDATE import_jobs SET status = 'interrupted', modified_at_utc = ? WHERE status = 'running'",
        [now],
      );
      final rows = database.select(
        'SELECT value_json FROM app_settings WHERE key = ?',
        [ImportRecoveryNotice.settingKey],
      );
      final previous = rows.isEmpty
          ? null
          : ImportRecoveryNotice.parse(rows.single['value_json'] as String);
      if (jobs > 0 || failures > 0 || (previous?.cleanupFailures ?? 0) > 0) {
        final generation = previous != null && previous.generation >= now
            ? previous.generation + 1
            : now;
        final raw = jsonEncode({
          'version': 1,
          'generation': generation,
          'interruptedJobs': jobs + (previous?.interruptedJobs ?? 0),
          'cleanupFailures': failures,
        });
        if (jobs + (previous?.interruptedJobs ?? 0) == 0 && failures == 0) {
          database.execute('DELETE FROM app_settings WHERE key = ?', [
            ImportRecoveryNotice.settingKey,
          ]);
        } else {
          database.execute(
            'INSERT INTO app_settings (key,value_json) VALUES (?,?) ON CONFLICT(key) DO UPDATE SET value_json = excluded.value_json',
            [ImportRecoveryNotice.settingKey, raw],
          );
        }
      }
      database.execute('COMMIT');
    } catch (_) {
      database.execute('ROLLBACK');
      rethrow;
    }
  }

  int _clean(Database database) {
    final media = Directory(p.join(root.path, 'media'));
    final imports = Directory(p.join(media.path, '.imports'));
    var failures = 0;
    try {
      if (FileSystemEntity.typeSync(media.path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return 0;
      }
      _ordinaryDirectory(media, root.resolveSymbolicLinksSync());
      if (FileSystemEntity.typeSync(imports.path, followLinks: false) ==
          FileSystemEntityType.notFound) {
        return 0;
      }
      final canonicalMedia = media.resolveSymbolicLinksSync();
      _ordinaryDirectory(imports, canonicalMedia);
      final canonicalImports = imports.resolveSymbolicLinksSync();
      Set<String>? protected;
      Set<String> protectedHashes() {
        if (protected != null) return protected!;
        final hashes = {
          for (final row in database.select('SELECT content_hash FROM media'))
            row['content_hash'] as String,
        };
        for (final row in database.select('SELECT fields_json FROM notes')) {
          hashes.addAll(
            mediaReferences(
              Map<String, String>.from(
                jsonDecode(row['fields_json'] as String) as Map,
              ),
            ),
          );
        }
        return protected = hashes;
      }

      for (final entity in imports.listSync(followLinks: false)) {
        if (!_stageName.hasMatch(p.basename(entity.path))) continue;
        try {
          final staging = Directory(entity.path);
          _ordinaryDirectory(staging, canonicalImports);
          final canonicalStage = staging.resolveSymbolicLinksSync();
          // Preflight the whole tree before deleting anything. Never follow
          // symlinks/junctions or recurse into an unexpected external target.
          final entries = staging.listSync(recursive: true, followLinks: false);
          for (final entry in entries) {
            final type = FileSystemEntity.typeSync(
              entry.path,
              followLinks: false,
            );
            if ((type != FileSystemEntityType.file &&
                    type != FileSystemEntityType.directory) ||
                !p.isWithin(canonicalStage, entry.resolveSymbolicLinksSync())) {
              throw const FormatException('Unsafe staging tree');
            }
          }
          final journal = File(p.join(staging.path, 'journal.json'));
          if (journal.existsSync()) {
            if (journal.lengthSync() > 16 * 1024 * 1024) {
              throw const FormatException('Oversized journal');
            }
            final value = jsonDecode(journal.readAsStringSync()) as Map;
            final hashes = value['newFiles'] as List;
            if (value['version'] != 1 ||
                hashes.any((h) => h is! String || !_hash.hasMatch(h))) {
              throw const FormatException('Invalid media journal');
            }
            final protected = hashes.isEmpty ? <String>{} : protectedHashes();
            final candidates = <File>[];
            for (final hash in hashes.toSet().difference(protected)) {
              final file = File(p.join(canonicalMedia, hash as String));
              final type = FileSystemEntity.typeSync(
                file.path,
                followLinks: false,
              );
              if (type == FileSystemEntityType.notFound) continue;
              if (type != FileSystemEntityType.file ||
                  p.dirname(file.resolveSymbolicLinksSync()) !=
                      canonicalMedia) {
                throw const FormatException('Unsafe media candidate');
              }
              candidates.add(file);
            }
            for (final file in candidates) {
              file.deleteSync();
            }
          }
          entries.sort((a, b) => b.path.length.compareTo(a.path.length));
          for (final entry in entries) {
            entry.deleteSync();
          }
          staging.deleteSync();
        } on FileSystemException {
          failures++;
        } on FormatException {
          failures++;
        } on TypeError {
          failures++;
        }
      }
    } on FileSystemException {
      failures++;
    } on FormatException {
      failures++;
    }
    return failures;
  }

  void _ordinaryDirectory(Directory directory, String canonicalParent) {
    if (FileSystemEntity.typeSync(directory.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        p.dirname(directory.resolveSymbolicLinksSync()) != canonicalParent) {
      throw const FormatException('Unsafe recovery directory');
    }
  }
}
