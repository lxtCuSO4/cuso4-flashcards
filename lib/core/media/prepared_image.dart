import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Validated, bounded, memory-only image draft. Never retains a picker path.
class PreparedImage {
  PreparedImage._(this.bytes, this.name, this.mimeType)
    : hash = sha256.convert(bytes).toString();

  static const maxBytes = 10 * 1024 * 1024;
  static const maxDraftBytes = 30 * 1024 * 1024;
  static const maxPixels = 16000000;
  final Uint8List bytes;
  final String name;
  final String mimeType;
  final String hash;
  String get token => 'media:$hash';

  static Future<PreparedImage> fromBytes(
    Uint8List source, {
    required String name,
  }) async {
    if (source.isEmpty || source.length > maxBytes) {
      throw ArgumentError('单张图片须小于或等于 10 MiB。');
    }
    final bytes = Uint8List.fromList(source).asUnmodifiableView();
    bool starts(List<int> prefix) =>
        bytes.length >= prefix.length &&
        List.generate(
          prefix.length,
          (i) => bytes[i] == prefix[i],
        ).every((v) => v);
    bool asciiAt(int offset, String value) =>
        bytes.length >= offset + value.length &&
        List.generate(
          value.length,
          (i) => bytes[offset + i] == value.codeUnitAt(i),
        ).every((v) => v);
    final mime = starts([137, 80, 78, 71, 13, 10, 26, 10])
        ? 'image/png'
        : starts([255, 216, 255])
        ? 'image/jpeg'
        : asciiAt(0, 'GIF87a') || asciiAt(0, 'GIF89a')
        ? 'image/gif'
        : asciiAt(0, 'RIFF') && asciiAt(8, 'WEBP')
        ? 'image/webp'
        : null;
    if (mime == null) throw ArgumentError('请选择 PNG、JPG、GIF 或 WebP 图片。');
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      if (descriptor.width * descriptor.height > maxPixels) {
        throw ArgumentError('图片超过 1600 万像素，请缩小后再插入。');
      }
      codec = await descriptor.instantiateCodec(
        targetWidth: 1,
        targetHeight: 1,
      );
      final frame = await codec.getNextFrame();
      frame.image.dispose();
    } on ArgumentError {
      rethrow;
    } catch (_) {
      throw ArgumentError('图片损坏或无法读取，请选择另一张图片。');
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
    return PreparedImage._(bytes, p.basename(name), mime);
  }
}
