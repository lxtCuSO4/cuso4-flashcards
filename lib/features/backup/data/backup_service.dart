import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import '../domain/backup_manifest.dart';
import 'backup_archive.dart';
import 'database_snapshot_service.dart';

class BackupService {
  BackupService(this.db, this.root, {this.availableBytes});
  final AppDatabase db;
  final Directory root;
  final AvailableBytes? availableBytes;

  Future<File> create({
    bool Function()? isCancelled,
    void Function(String)? onProgress,
    Directory? recoveryRoot,
  }) async {
    checkBackupCanceled(isCancelled);
    final rows = await db
        .customSelect('SELECT SUM(byte_length) AS bytes FROM media')
        .getSingle();
    final pageCount = await db.customSelect('PRAGMA page_count').getSingle();
    final pageSize = await db.customSelect('PRAGMA page_size').getSingle();
    var estimate =
        (rows.readNullable<int>('bytes') ?? 0) +
        pageCount.read<int>('page_count') * pageSize.read<int>('page_size');
    if (recoveryRoot != null) {
      estimate = 0;
      await for (final entity in recoveryRoot.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          estimate += await entity.length();
        } else if (entity is! Directory) {
          throw invalidBackup;
        }
      }
    }
    await requireBackupSpace(availableBytes, estimate * 3);
    final parent = await Directory(p.join(root.path, 'backup-work'))
        .create(recursive: true);
    final job = await parent.createTemp('export-');
    try {
      onProgress?.call('制作数据库一致性快照');
      final snapshot = File(p.join(job.path, 'snapshot.sqlite'));
      if (recoveryRoot == null) {
        await DatabaseSnapshotService.create(db, snapshot);
      } else {
        final source = p.join(recoveryRoot.path, 'cuso4.sqlite');
        final target = snapshot.path;
        await Isolate.run(
          () => DatabaseSnapshotService.fromRecovery(source, target),
        );
      }
      checkBackupCanceled(isCancelled);
      onProgress?.call('打包卡片、进度与媒体');
      final source = snapshot.path;
      final media = p.join((recoveryRoot ?? root).path, 'media');
      final output = p.join(
        job.path,
        'CuSO4-${DateTime.now().toUtc().millisecondsSinceEpoch}.cuso4backup',
      );
      await Isolate.run(() => BackupArchive.encode(source, media, output));
      checkBackupCanceled(isCancelled);
      onProgress?.call('校验完整备份');
      final verify = p.join(job.path, 'verify');
      await Isolate.run(() => BackupArchive.extract(output, verify));
      checkBackupCanceled(isCancelled);
      await Directory(verify).delete(recursive: true);
      await snapshot.delete();
      return File(output);
    } catch (_) {
      await job.delete(recursive: true);
      rethrow;
    }
  }

  static Future<void> discard(File file) async {
    // Only dispose an export job created by this service, never the chosen destination.
    if (p.basename(file.parent.parent.path) != 'backup-work' ||
        !p.basename(file.parent.path).startsWith('export-')) {
      return;
    }
    if (await file.parent.exists()) await file.parent.delete(recursive: true);
  }
}
