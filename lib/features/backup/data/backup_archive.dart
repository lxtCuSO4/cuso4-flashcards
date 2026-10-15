import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:html/parser.dart' as html;
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../../../core/database/app_database.dart';
import '../../decks/domain/choice_question.dart';
import '../../decks/domain/note.dart';
import '../domain/backup_manifest.dart';

/// File-backed ZIP and hashing work is invoked on a worker isolate.
class BackupArchive {
  static Future<BackupEntry> describe(File file) async => BackupEntry(
    hash: (await sha256.bind(file.openRead()).first).toString(),
    bytes: await file.length(),
  );

  static Map<String, int> referencedMedia(Database db) {
    final hashes = <String>{};
    final token = RegExp(r'^media:([a-f0-9]{64})$');
    final sound = RegExp(r'\[sound:media:([a-f0-9]{64})\]');
    for (final note in db.select('SELECT fields_json FROM notes')) {
      final fields = Map<String, String>.from(
        jsonDecode(note['fields_json'] as String) as Map,
      );
      for (final value in fields.values) {
        final fragment = html.parseFragment(value);
        for (final image in fragment.querySelectorAll('img')) {
          final match = token.firstMatch(image.attributes['src'] ?? '');
          if (match != null) hashes.add(match[1]!);
        }
        hashes.addAll(sound.allMatches(fragment.text ?? '').map((m) => m[1]!));
      }
    }
    final result = <String, int>{};
    for (final hash in hashes) {
      final rows = db.select(
        'SELECT relative_path, byte_length FROM media WHERE content_hash=?',
        [hash],
      );
      if (rows.length != 1 ||
          rows.single['relative_path'] != hash ||
          rows.single['byte_length'] is! int ||
          (rows.single['byte_length'] as int) < 0) {
        throw const BackupException(
          BackupErrorCode.invalidArchive,
          '有卡片引用的媒体记录缺失，请修复对应卡片后重试备份。',
        );
      }
      result[hash] = rows.single['byte_length'] as int;
    }
    return result;
  }

  static Future<void> validateDatabase(File file) async {
    final db = sqlite3.open(file.path, mode: OpenMode.readOnly);
    final expected = AppDatabase(NativeDatabase.memory());
    try {
      db.execute('PRAGMA trusted_schema=OFF');
      if (db.select('PRAGMA user_version').single.values.single != 1 ||
          db
              .select('PRAGMA integrity_check')
              .any((r) => r.values.single != 'ok') ||
          db.select('PRAGMA foreign_key_check').isNotEmpty) {
        throw invalidBackup;
      }
      const query =
          "SELECT name, sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY name";
      final schema = db
          .select(query)
          .map((r) => [r['name'], r['sql']])
          .toList();
      final reference = (await expected.customSelect(query).get())
          .map((r) => [r.data['name'], r.data['sql']])
          .toList();
      // Reject additional views/triggers/altered constraints, not just missing tables.
      if (jsonEncode(schema) != jsonEncode(reference)) throw invalidBackup;
      for (final row in db.select('SELECT note_type, fields_json FROM notes')) {
        final type = row['note_type'];
        if (type is! int || type < 0 || type >= NoteType.values.length) {
          throw invalidBackup;
        }
        if (NoteType.values[type].isChoice) {
          try {
            ChoiceQuestion.fromFields(
              NoteType.values[type],
              Map<String, String>.from(
                jsonDecode(row['fields_json'] as String) as Map,
              ),
            );
          } catch (_) {
            throw invalidBackup;
          }
        }
      }
      referencedMedia(db);
    } finally {
      db.close();
      await expected.close();
    }
  }

  static Future<void> encode(
    String snapshotPath,
    String mediaPath,
    String outputPath,
  ) async {
    final snapshot = File(snapshotPath);
    await validateDatabase(snapshot);
    final db = sqlite3.open(snapshot.path, mode: OpenMode.readOnly);
    final encoder = ZipFileEncoder();
    var opened = false;
    try {
      final refs = referencedMedia(db);
      final media = <String, BackupEntry>{};
      final database = await describe(snapshot);
      var total = database.bytes;
      encoder.create(outputPath);
      opened = true;
      await encoder.addFile(snapshot, 'database.sqlite');
      for (final entry in refs.entries) {
        final file = File(p.join(mediaPath, entry.key));
        if (await FileSystemEntity.type(file.path, followLinks: false) !=
                FileSystemEntityType.file ||
            !await Directory(mediaPath).exists() ||
            p.dirname(await file.resolveSymbolicLinks()) !=
                await Directory(mediaPath).resolveSymbolicLinks()) {
          throw const BackupException(
            BackupErrorCode.invalidArchive,
            '有卡片引用的媒体文件缺失，未生成不完整备份。',
          );
        }
        final info = await describe(file);
        total += info.bytes;
        if (info.hash != entry.key || info.bytes != entry.value) {
          throw const BackupException(
            BackupErrorCode.checksumMismatch,
            '本机媒体文件校验失败，请保留现有数据并检查对应卡片。',
          );
        }
        if (total > maxBackupBytes || refs.length > 49998) throw invalidBackup;
        media[entry.key] = info;
        await encoder.addFile(file, 'media/${entry.key}');
      }
      final manifest = BackupManifest(
        createdAtUtc: DateTime.now().toUtc(),
        database: database,
        media: media,
      );
      encoder.addArchiveFile(
        ArchiveFile.string('manifest.json', jsonEncode(manifest.toJson())),
      );
    } finally {
      db.close();
      if (opened) await encoder.close();
    }
  }

  static Future<void> extract(String sourcePath, String destinationPath) async {
    final input = InputFileStream(sourcePath);
    try {
      final decoder = ZipDecoder();
      final archive = decoder.decodeStream(input);
      if (decoder.directory.filePosition < 0 ||
          archive.length < 2 ||
          archive.length > 50000 ||
          archive.length != decoder.directory.fileHeaders.length) {
        throw invalidBackup;
      }
      var total = 0;
      for (final entry in archive) {
        if (!entry.isFile ||
            entry.isSymbolicLink ||
            !_safeName(entry.name) ||
            entry.size < 0 ||
            total + entry.size > maxBackupBytes ||
            entry.name == 'manifest.json' && entry.size > 8 * 1024 * 1024) {
          throw invalidBackup;
        }
        total += entry.size;
        final file = File(
          p.join(
            destinationPath,
            entry.name == 'database.sqlite' ? 'cuso4.sqlite' : entry.name,
          ),
        );
        await file.parent.create(recursive: true);
        final sink = _BackupOutput(file.path, entry.size);
        try {
          entry.writeContent(sink);
        } finally {
          sink.closeSync();
        }
        if (sink.length != entry.size || sink.checksum != entry.crc32) {
          throw invalidBackup;
        }
      }
      await validateExtracted(
        Directory(destinationPath),
        archive.map((f) => f.name).toSet(),
      );
    } on BackupException {
      rethrow;
    } catch (_) {
      throw invalidBackup;
    } finally {
      input.closeSync();
    }
  }

  static bool _safeName(String name) =>
      name == 'manifest.json' ||
      name == 'database.sqlite' ||
      RegExp(r'^media/[a-f0-9]{64}$').hasMatch(name);

  static Future<void> validateExtracted(
    Directory root,
    Set<String> names,
  ) async {
    final manifest = BackupManifest.fromJson(
      jsonDecode(await File(p.join(root.path, 'manifest.json')).readAsString()),
    );
    final expected = {
      'manifest.json',
      'database.sqlite',
      ...manifest.media.keys.map((h) => 'media/$h'),
    };
    if (names.length != expected.length || !names.containsAll(expected)) {
      throw invalidBackup;
    }
    Future<void> verify(File file, BackupEntry entry) async {
      final actual = await describe(file);
      if (actual.bytes != entry.bytes || actual.hash != entry.hash) {
        throw const BackupException(
          BackupErrorCode.checksumMismatch,
          '备份校验失败：文件可能损坏。现有数据未被覆盖。',
        );
      }
    }

    final database = File(p.join(root.path, 'cuso4.sqlite'));
    await verify(database, manifest.database);
    for (final entry in manifest.media.entries) {
      await verify(File(p.join(root.path, 'media', entry.key)), entry.value);
    }
    await validateDatabase(database);
    final db = sqlite3.open(database.path, mode: OpenMode.readOnly);
    try {
      final refs = referencedMedia(db);
      if (refs.length != manifest.media.length ||
          refs.entries.any((e) => manifest.media[e.key]?.bytes != e.value)) {
        throw invalidBackup;
      }
    } finally {
      db.close();
    }
    await Directory(p.join(root.path, 'media')).create(recursive: true);
  }

  static Future<void> validateStage(String path) async {
    final root = Directory(path);
    final names = <String>{};
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      final relative = p
          .relative(entity.path, from: path)
          .split(p.separator)
          .join('/');
      if (entity is Directory && relative == 'media') continue;
      if (entity is! File) throw invalidBackup;
      names.add(relative == 'cuso4.sqlite' ? 'database.sqlite' : relative);
    }
    await validateExtracted(root, names);
  }
}

class _BackupOutput extends OutputFileStream {
  _BackupOutput(String path, this.limit)
    : super.withFileHandle(FileHandle(path, mode: FileAccess.write));
  final int limit;
  int checksum = 0;
  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    if (count < 0 || this.length + count > limit) throw invalidBackup;
    checksum = getCrc32(
      count == bytes.length ? bytes : bytes.sublist(0, count),
      checksum,
    );
    super.writeBytes(bytes, length: count);
  }

  @override
  void writeByte(int value) => writeBytes([value]);
}
