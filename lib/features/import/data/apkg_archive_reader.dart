import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../domain/import_error.dart';

class ApkgPackage {
  const ApkgPackage({
    required this.root,
    required this.collectionPath,
    required this.mediaFiles,
    required this.temporary,
  });
  final Directory root;
  final File collectionPath;
  final Map<String, File> mediaFiles;
  final bool temporary;
  Future<void> dispose() async {
    if (temporary && await root.exists()) await root.delete(recursive: true);
  }
}

class ApkgArchiveReader {
  ApkgArchiveReader({
    this.maxEntries = 50000,
    this.maxExtractedBytes = 512 * 1024 * 1024,
  });
  final int maxEntries;
  final int maxExtractedBytes;

  Future<ApkgPackage> extract(File source, {Directory? destination}) async {
    if (!await source.exists() ||
        p.extension(source.path).toLowerCase() != '.apkg') {
      throw const ApkgImportException(
        ImportErrorCode.invalidArchive,
        '请选择 .apkg 牌组包。',
      );
    }
    if (await source.length() > maxExtractedBytes) {
      throw const ApkgImportException(
        ImportErrorCode.invalidArchive,
        '牌组包超过导入大小上限。',
      );
    }
    final parent = destination ?? Directory.systemTemp;
    await parent.create(recursive: true);
    final root = await parent.createTemp('cuso4_apkg_');
    final input = InputFileStream(source.path);
    try {
      final decoder = ZipDecoder();
      final archive = decoder.decodeStream(input);
      if (decoder.directory.filePosition < 0) {
        throw const ApkgImportException(
          ImportErrorCode.damagedArchive,
          '牌组包损坏或不是有效的 ZIP 文件。',
        );
      }
      if (decoder.directory.fileHeaders.length != archive.length ||
          archive.any((e) => e.isSymbolicLink)) {
        throw const ApkgImportException(
          ImportErrorCode.damagedArchive,
          '牌组包包含重复文件或符号链接。',
        );
      }
      if (archive.length > maxEntries) {
        throw const ApkgImportException(
          ImportErrorCode.invalidArchive,
          '牌组包包含过多文件。',
        );
      }
      if (archive.find('collection.anki21b') != null) {
        throw const ApkgImportException(
          ImportErrorCode.unsupportedCollectionVersion,
          '该牌组使用新版压缩格式。请在 Anki 导出时选择旧版兼容格式。',
        );
      }
      final collectionName = archive.find('collection.anki21') != null
          ? 'collection.anki21'
          : 'collection.anki2';
      var extracted = 0;
      for (final entry in archive) {
        if (entry.isDirectory) continue;
        final normalized = _safeName(entry.name);
        if (entry.size < 0 || extracted + entry.size > maxExtractedBytes) {
          throw const ApkgImportException(
            ImportErrorCode.invalidArchive,
            '牌组包解压后超过大小上限。',
          );
        }
        final output = File(p.join(root.path, normalized));
        await output.parent.create(recursive: true);
        final sink = _CheckedOutput(output.path, maxExtractedBytes - extracted);
        try {
          entry.writeContent(sink);
        } finally {
          sink.closeSync();
        }
        if (sink.length != entry.size || sink.checksum != entry.crc32) {
          throw const ApkgImportException(
            ImportErrorCode.damagedArchive,
            '牌组包文件校验失败。',
          );
        }
        extracted += sink.length;
      }
      final collection = File(p.join(root.path, collectionName));
      if (!await collection.exists()) {
        throw const ApkgImportException(
          ImportErrorCode.missingCollection,
          '牌组包缺少集合数据库。',
        );
      }
      final manifestFile = File(p.join(root.path, 'media'));
      final media = <String, File>{};
      if (await manifestFile.exists()) {
        try {
          if (await manifestFile.length() > 8 * 1024 * 1024) {
            throw const FormatException();
          }
          final manifest = jsonDecode(
            await manifestFile.readAsString(),
          ) as Map<String, dynamic>;
          for (final entry in manifest.entries) {
            if (!RegExp(r'^\d+$').hasMatch(entry.key) ||
                entry.value is! String) {
              throw const FormatException();
            }
            final name = entry.value as String;
            _safeName(name);
            if (name.contains('/') ||
                name.contains('\\') ||
                media.containsKey(name)) {
              throw const FormatException();
            }
            media[name] = File(p.join(root.path, entry.key));
          }
        } catch (_) {
          throw const ApkgImportException(
            ImportErrorCode.invalidMediaManifest,
            '牌组媒体清单损坏。',
          );
        }
      }
      return ApkgPackage(
        root: root,
        collectionPath: collection,
        mediaFiles: media,
        temporary: true,
      );
    } catch (error) {
      if (await root.exists()) await root.delete(recursive: true);
      if (error is ApkgImportException) rethrow;
      throw ApkgImportException(
        ImportErrorCode.damagedArchive,
        '牌组包损坏或不是有效的 ZIP 文件。',
      );
    } finally {
      input.closeSync();
    }
  }

  String _safeName(String name) {
    final value = name.replaceAll('\\', '/');
    final segments = value.split('/');
    if (value.isEmpty ||
        value.contains(':') ||
        value.contains('\u0000') ||
        value.startsWith('/') ||
        segments.contains('..') ||
        segments.contains('.') ||
        segments.contains('')) {
      throw const ApkgImportException(
        ImportErrorCode.damagedArchive,
        '牌组包包含不安全的文件路径。',
      );
    }
    return segments.join('/');
  }
}

/// Enforces the real inflated size and CRC, even if ZIP headers are dishonest.
class _CheckedOutput extends OutputFileStream {
  _CheckedOutput(String path, this.limit)
    : super.withFileHandle(FileHandle(path, mode: FileAccess.write));
  final int limit;
  int checksum = 0;
  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    if (this.length + count > limit) {
      throw const ApkgImportException(
        ImportErrorCode.invalidArchive,
        '牌组解压数据超过上限。',
      );
    }
    checksum = getCrc32(
      count == bytes.length ? bytes : bytes.sublist(0, count),
      checksum,
    );
    super.writeBytes(bytes, length: count);
  }

  @override
  void writeByte(int value) => writeBytes([value]);
}
