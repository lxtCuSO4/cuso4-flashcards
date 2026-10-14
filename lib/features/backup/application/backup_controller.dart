import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../../../core/database/app_database.dart';
import '../data/backup_platform.dart';
import '../data/backup_service.dart';
import '../data/restore_service.dart';
import '../domain/backup_manifest.dart';

class BackupController extends ChangeNotifier {
  BackupController({
    required this.database,
    required this.root,
    required this.platform,
    required this.importBusy,
    required this.databaseChanged,
  });
  final AppDatabase Function() database;
  final Future<Directory> Function() root;
  final BackupPlatform platform;
  final bool Function() importBusy;
  final void Function() databaseChanged;
  bool busy = false;
  bool canCancel = false;
  bool restored = false;
  bool hasRecovery = false;
  String? progress;
  String? message;
  String? error;
  bool _cancel = false;
  bool _disposed = false;

  Future<void> refreshRecovery() async {
    final folder = await root();
    hasRecovery = await File(
      p.join(folder.path, '.cuso4-recovery', 'cuso4.sqlite'),
    ).exists();
    _notify();
  }

  bool _begin() {
    if (busy) return false;
    error = null;
    message = null;
    restored = false;
    if (importBusy()) {
      error = '请等待当前牌组导入完成或取消导入后再操作。';
      _notify();
      return false;
    }
    busy = true;
    canCancel = true;
    _cancel = false;
    _notify();
    return true;
  }

  void _progress(String value) {
    progress = value;
    _notify();
  }

  void cancel() {
    if (busy && canCancel) {
      _cancel = true;
      _progress('正在取消，当前校验或打包步骤结束后退出');
    }
  }

  Future<void> export({bool previous = false}) async {
    if (!_begin()) return;
    File? archive;
    try {
      final folder = await root();
      final recovery = previous
          ? Directory(p.join(folder.path, '.cuso4-recovery'))
          : null;
      archive =
          await BackupService(
            database(),
            folder,
            availableBytes: platform.availableBytes,
          ).create(
            isCancelled: () => _cancel,
            onProgress: _progress,
            recoveryRoot: recovery,
          );
      checkBackupCanceled(() => _cancel);
      canCancel = false;
      _progress('选择保存位置');
      final bytes = await archive.length();
      final saved = await platform.saveBackup(archive);
      if (saved) {
        final db = database();
        if (!previous) {
          await db.transaction(() async {
            for (final item in {
              'lastBackupUtc': DateTime.now().toUtc().toIso8601String(),
              'lastBackupBytes': '$bytes',
            }.entries) {
              await db
                  .into(db.appSettings)
                  .insertOnConflictUpdate(
                    AppSettingsCompanion.insert(
                      key: item.key,
                      valueJson: item.value,
                    ),
                  );
            }
          });
        }
        message = previous ? '恢复前快照已导出，请妥善保存。' : '备份已保存，包含卡片、媒体、设置和学习进度。';
      } else {
        message = '已取消保存，现有数据未改变。';
      }
    } catch (e) {
      _recordError(e);
    } finally {
      if (archive != null) {
        try {
          await BackupService.discard(archive);
        } on FileSystemException {
          /* retryable temporary file */
        }
      }
      _finish();
    }
  }

  Future<void> restore({required Future<bool> Function() confirm}) async {
    if (!_begin()) return;
    Directory? stage;
    var closed = false;
    try {
      _progress('选择 .cuso4backup 备份文件');
      final source = await platform.pickRestoreFile();
      if (source == null) {
        message = '已取消选择。';
        return;
      }
      checkBackupCanceled(() => _cancel);
      final folder = await root();
      final service = RestoreService(
        folder,
        availableBytes: platform.availableBytes,
      );
      stage = await service.prepare(
        source,
        isCancelled: () => _cancel,
        onProgress: _progress,
      );
      canCancel = false;
      _progress('备份校验通过，等待确认');
      if (!await confirm()) {
        message = '已取消恢复，现有数据未改变。';
        return;
      }
      checkBackupCanceled(() => _cancel);
      if (importBusy()) throw StateError('import in progress');
      _progress('保留恢复前快照并切换数据，请勿关闭应用');
      await database().close();
      closed = true;
      await service.apply(stage);
      databaseChanged();
      closed = false;
      await database()
          .customSelect('SELECT COUNT(*) AS count FROM cards')
          .get();
      hasRecovery = true;
      restored = true;
      message = '恢复完成。恢复前的数据已保留为本机安全快照。';
    } catch (e) {
      _recordError(e);
    } finally {
      if (closed) databaseChanged();
      if (stage != null && await stage.exists()) {
        try {
          await stage.delete(recursive: true);
        } on FileSystemException {
          /* startup cleanup */
        }
      }
      _finish();
    }
  }

  void _recordError(Object e) {
    if (e is BackupException) {
      if (e.code == BackupErrorCode.canceled) {
        message = e.message;
      } else {
        error = e.message;
      }
    } else {
      error = '操作未完成。请保留应用数据，检查文件和可用空间后重试。';
    }
  }

  void _finish() {
    busy = false;
    canCancel = false;
    progress = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel = true;
    super.dispose();
  }
}
