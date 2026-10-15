import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

class BackupPlatform {
  static const _channel = MethodChannel('com.cuso4.flashcards/backup');

  Future<int?> availableBytes() async {
    if (!Platform.isAndroid) return null;
    return await _channel.invokeMethod<int>('availableBytes');
  }

  Future<File?> pickRestoreFile() async {
    final result = await FilePicker.pickFile(dialogTitle: '选择 Lunar Memory 备份');
    final path = result?.path;
    return path == null ? null : File(path);
  }

  Future<bool> saveBackup(File file) async =>
      await _channel.invokeMethod<bool>('saveBackup', {
        'path': file.path,
        'name': file.uri.pathSegments.last,
      }) ??
      false;
}
