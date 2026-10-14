import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../domain/backup_manifest.dart';
import 'backup_archive.dart';

class RestoreService {
  RestoreService(this.root, {this.availableBytes, this.afterMove});
  final Directory root;
  final AvailableBytes? availableBytes;
  final void Function(int)? afterMove;
  static const _names = [
    'cuso4.sqlite',
    'cuso4.sqlite-wal',
    'cuso4.sqlite-shm',
    'media',
  ];

  Future<Directory> prepare(
    File source, {
    bool Function()? isCancelled,
    void Function(String)? onProgress,
  }) async {
    checkBackupCanceled(isCancelled);
    if (p.extension(source.path).toLowerCase() != '.cuso4backup' ||
        !await source.exists() ||
        await source.length() > maxBackupBytes) {
      throw invalidBackup;
    }
    onProgress?.call('检查备份版本与所需空间');
    final sourcePath = source.path;
    final required = await Isolate.run(() {
      final input = InputFileStream(sourcePath);
      try {
        final decoder = ZipDecoder();
        final archive = decoder.decodeStream(input);
        if (decoder.directory.filePosition < 0 || archive.length > 50000) {
          throw invalidBackup;
        }
        final sum = archive.fold(0, (int sum, entry) => sum + entry.size);
        if (sum < 0 || sum > maxBackupBytes) throw invalidBackup;
        return sum;
      } catch (_) {
        throw invalidBackup;
      } finally {
        input.closeSync();
      }
    });
    await requireBackupSpace(availableBytes, required);
    checkBackupCanceled(isCancelled);
    final parent = await Directory(p.join(root.path, 'backup-work'))
        .create(recursive: true);
    final stage = await parent.createTemp('restore-');
    try {
      onProgress?.call('解压并校验数据库与媒体');
      final destination = stage.path;
      await Isolate.run(() => BackupArchive.extract(sourcePath, destination));
      checkBackupCanceled(isCancelled);
      return stage;
    } catch (_) {
      await stage.delete(recursive: true);
      rethrow;
    }
  }

  /// Caller must close every live database connection before this method.
  Future<void> apply(Directory stage) async {
    if (p.dirname(stage.path) != p.join(root.path, 'backup-work') ||
        !p.basename(stage.path).startsWith('restore-')) {
      throw invalidBackup;
    }
    await requireBackupSpace(availableBytes, 0);
    final stagePath = stage.path;
    await Isolate.run(() => BackupArchive.validateStage(stagePath));
    recoverInterrupted(root);
    final job = Directory(p.join(root.path, '.cuso4-restore'));
    final previous = Directory(p.join(job.path, 'previous'));
    await previous.create(recursive: true);
    final existed = <String, bool>{};
    for (final name in _names) {
      final type = FileSystemEntity.typeSync(
        p.join(root.path, name),
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound &&
          type !=
              (name == 'media'
                  ? FileSystemEntityType.directory
                  : FileSystemEntityType.file)) {
        throw invalidBackup;
      }
      existed[name] = type != FileSystemEntityType.notFound;
    }
    _writeJournal(job, {'phase': 'replacing', 'existed': existed});
    var step = 0;
    try {
      for (final name in _names) {
        if (existed[name]!) {
          _move(p.join(root.path, name), p.join(previous.path, name));
          afterMove?.call(++step);
        }
      }
      for (final name in ['cuso4.sqlite', 'media']) {
        _move(p.join(stage.path, name), p.join(root.path, name));
        afterMove?.call(++step);
      }
      await BackupArchive.validateDatabase(
        File(p.join(root.path, 'cuso4.sqlite')),
      );
      _writeJournal(job, {'phase': 'committed', 'existed': existed});
    } catch (_) {
      recoverInterrupted(root);
      rethrow;
    }
    // Once committed, cleanup errors are retried on startup, not reported as a failed restore.
    try {
      _finishCommitted(root, job);
    } on FileSystemException {
      /* retained for startup */
    }
    if (await stage.exists()) await stage.delete(recursive: true);
  }

  static void _writeJournal(Directory job, Map<String, Object> value) {
    final next = File(p.join(job.path, 'journal.next'));
    next.writeAsStringSync(jsonEncode(value), flush: true);
    next.renameSync(p.join(job.path, 'journal.json'));
  }

  static void _move(String from, String to) {
    final type = FileSystemEntity.typeSync(from, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      Directory(from).renameSync(to);
    } else if (type == FileSystemEntityType.file) {
      File(from).renameSync(to);
    } else {
      throw invalidBackup;
    }
  }

  static void _remove(String path) {
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      Directory(path).deleteSync(recursive: true);
    } else if (type == FileSystemEntityType.file) {
      File(path).deleteSync();
    } else if (type != FileSystemEntityType.notFound) {
      throw invalidBackup;
    }
  }

  /// Runs before opening SQLite. An uncommitted multi-file replacement always rolls back.
  /// All paths are fixed children of app support; a damaged journal fails closed.
  static void recoverInterrupted(Directory root) {
    final job = Directory(p.join(root.path, '.cuso4-restore'));
    if (!job.existsSync()) return;
    if (FileSystemEntity.typeSync(job.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw invalidBackup;
    }
    final journal = File(p.join(job.path, 'journal.json'));
    if (!journal.existsSync()) {
      // No journal means no live file was moved (journal is flushed first).
      job.deleteSync(recursive: true);
      return;
    }
    final dynamic value;
    try {
      value = jsonDecode(journal.readAsStringSync());
    } catch (_) {
      throw const BackupException(
        BackupErrorCode.invalidArchive,
        '恢复记录损坏。为保护数据，已停止打开数据库，请保留应用数据。',
      );
    }
    if (value is! Map ||
        !['replacing', 'committed'].contains(value['phase']) ||
        value['existed'] is! Map ||
        _names.any((name) => value['existed'][name] is! bool)) {
      throw invalidBackup;
    }
    if (value['phase'] == 'committed') {
      try {
        _finishCommitted(root, job);
      } on FileSystemException {
        /* retry cleanup without blocking healthy data */
      }
      return;
    }
    final previous = Directory(p.join(job.path, 'previous'));
    for (final name in _names) {
      final original = p.join(previous.path, name);
      final target = p.join(root.path, name);
      if (FileSystemEntity.typeSync(original, followLinks: false) !=
          FileSystemEntityType.notFound) {
        _remove(target);
        _move(original, target);
      } else if (value['existed'][name] == false) {
        _remove(target);
      }
    }
    job.deleteSync(recursive: true);
  }

  static void _finishCommitted(Directory root, Directory job) {
    final previous = Directory(p.join(job.path, 'previous'));
    if (previous.existsSync()) {
      final recovery = p.join(root.path, '.cuso4-recovery');
      _remove(recovery);
      previous.renameSync(recovery);
    }
    job.deleteSync(recursive: true);
  }

  /// Call once before runApp, never while a backup/restore job is active.
  static void cleanAbandonedJobs(Directory root) {
    final work = Directory(p.join(root.path, 'backup-work'));
    if (FileSystemEntity.typeSync(work.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      return;
    }
    for (final entity in work.listSync(followLinks: false)) {
      final name = p.basename(entity.path);
      if (entity is Directory &&
          (name.startsWith('export-') || name.startsWith('restore-'))) {
        entity.deleteSync(recursive: true);
      }
    }
  }
}
