import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/import_error.dart';
import '../domain/import_progress.dart';
import '../domain/import_report.dart';

typedef ImportRunner = Future<ImportReport> Function(
  File file, {
  required bool merge,
  required bool Function() isCancelled,
  required void Function(ImportProgress) onProgress,
});

/// App-scoped: routing away cannot dispose a live import or start a second one.
class ImportController extends ChangeNotifier {
  ImportController(this._run);
  final ImportRunner _run;
  File? _file;
  bool _busy = false;
  bool _cancelRequested = false;
  bool _disposed = false;
  bool _merge = false;
  ImportProgress? _progress;
  ImportReport? _report;
  String? _error;

  File? get file => _file;
  bool get busy => _busy;
  bool get cancelRequested => _cancelRequested;
  bool get merge => _merge;
  ImportProgress? get progress => _progress;
  ImportReport? get report => _report;
  String? get error => _error;

  void select(File file) {
    if (_busy) return;
    _file = file;
    _report = null;
    _error = null;
    _progress = null;
    _notify();
  }

  void setMerge(bool value) {
    if (_busy) return;
    _merge = value;
    _notify();
  }

  void selectionFailed(String message) {
    if (_busy) return;
    _file = null;
    _report = null;
    _error = message;
    _notify();
  }

  Future<void> start() async {
    final source = _file;
    if (_busy || source == null) return;
    _busy = true;
    _cancelRequested = false;
    _report = null;
    _error = null;
    _notify();
    try {
      _report = await _run(
        source,
        merge: _merge,
        isCancelled: () => _cancelRequested,
        onProgress: (value) {
          _progress = value;
          _notify();
        },
      );
    } on ApkgImportException catch (error) {
      _error = error.message;
    } catch (_) {
      _error = '导入未完成，请检查文件和可用存储空间后重试。';
    } finally {
      _busy = false;
      _notify();
    }
  }

  void cancel() {
    if (!_busy || _cancelRequested) return;
    _cancelRequested = true;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _cancelRequested = true;
    _disposed = true;
    super.dispose();
  }
}
