import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/media/prepared_image.dart';

final editorImagePickerProvider = Provider<Future<PreparedImage?> Function()>(
  (ref) => pickEditorImage,
);

Future<PreparedImage?> pickEditorImage() async {
  final selected = await FilePicker.pickFile(
    dialogTitle: '选择卡片图片',
    type: FileType.image,
  );
  if (selected == null) return null;
  if (selected.path == null) throw ArgumentError('无法读取图片，请先保存到手机本地。');
  final file = File(selected.path!);
  if (await file.length() > PreparedImage.maxBytes) {
    throw ArgumentError('单张图片须小于或等于 10 MiB。');
  }
  final builder = BytesBuilder(copy: false);
  await for (final chunk in file.openRead(0, PreparedImage.maxBytes + 1)) {
    builder.add(chunk);
  }
  return PreparedImage.fromBytes(builder.takeBytes(), name: selected.name);
}
