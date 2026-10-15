import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../domain/import_error.dart';

class ImportedMediaAsset {
  const ImportedMediaAsset({
    required this.originalName,
    required this.contentHash,
    required this.relativePath,
    required this.mimeType,
    required this.byteLength,
  });
  final String originalName;
  final String contentHash;
  final String relativePath;
  final String mimeType;
  final int byteLength;
}

class PreparedMediaImport {
  PreparedMediaImport({
    required this.mediaDirectory,
    required this.stagingDirectory,
    required this.assetsByName,
    required this.missingNames,
    required this.unsupportedNames,
  });
  final Directory mediaDirectory;
  final Directory stagingDirectory;
  final Map<String, ImportedMediaAsset> assetsByName;
  final Set<String> missingNames;
  final Set<String> unsupportedNames;
  final Set<String> _newFiles = {};

  Future<int> commit() async {
    final candidates = <String>[];
    for (final hash in assetsByName.values.map((a) => a.contentHash).toSet()) {
      if (!await File(p.join(mediaDirectory.path, hash)).exists()) {
        candidates.add(hash);
      }
    }
    // Persist ownership before the first rename: a killed process cannot run
    // rollback(), and SQLite cannot roll back filesystem moves.
    final journal = File(p.join(stagingDirectory.path, 'journal.next'));
    await journal.writeAsString(
      jsonEncode({'version': 1, 'newFiles': candidates}),
      flush: true,
    );
    await journal.rename(p.join(stagingDirectory.path, 'journal.json'));
    for (final hash
        in assetsByName.values.map((asset) => asset.contentHash).toSet()) {
      final target = File(p.join(mediaDirectory.path, hash));
      if (await target.exists()) continue;
      final staged = File(p.join(stagingDirectory.path, hash));
      try {
        await staged.rename(target.path);
        _newFiles.add(target.path);
      } on FileSystemException {
        if (!await target.exists()) rethrow;
      }
    }
    return _newFiles.length;
  }

  Future<void> complete() async {
    if (await stagingDirectory.exists()) {
      await stagingDirectory.delete(recursive: true);
    }
  }

  Future<void> rollback() async {
    for (final path in _newFiles) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }
    await complete();
  }
}

class MediaImporter {
  MediaImporter(this.mediaDirectory, {this.maxAssetBytes = 64 * 1024 * 1024});
  final Directory mediaDirectory;
  final int maxAssetBytes;

  Future<PreparedMediaImport> prepare(
    Map<String, File> available,
    Set<String> requested, {
    bool Function()? isCancelled,
    void Function(int)? onProgress,
  }) async {
    await mediaDirectory.create(recursive: true);
    final imports = Directory(p.join(mediaDirectory.path, '.imports'));
    await imports.create(recursive: true);
    final staging = await imports.createTemp('job_');
    final assets = <String, ImportedMediaAsset>{};
    final missing = <String>{};
    final unsupported = <String>{};
    try {
      var count = 0;
      for (final name in requested) {
        if (isCancelled?.call() ?? false) {
          throw const ApkgImportException(
            ImportErrorCode.cancelled,
            '已取消导入，本次内容未保存。',
          );
        }
        onProgress?.call(count++);
        final source = available[name];
        if (source == null || !await source.exists()) {
          missing.add(name);
          continue;
        }
        final length = await source.length();
        if (length > maxAssetBytes) {
          unsupported.add(name);
          continue;
        }
        final mime = await _detectMimeType(source, name);
        if (mime == null) {
          unsupported.add(name);
          continue;
        }
        final hash = (await sha256.bind(source.openRead()).first).toString();
        final staged = File(p.join(staging.path, hash));
        if (!await staged.exists()) await source.copy(staged.path);
        assets[name] = ImportedMediaAsset(
          originalName: name,
          contentHash: hash,
          relativePath: hash,
          mimeType: mime,
          byteLength: length,
        );
      }
      onProgress?.call(requested.length);
      return PreparedMediaImport(
        mediaDirectory: mediaDirectory,
        stagingDirectory: staging,
        assetsByName: Map.unmodifiable(assets),
        missingNames: Set.unmodifiable(missing),
        unsupportedNames: Set.unmodifiable(unsupported),
      );
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<String?> _detectMimeType(File source, String name) async {
    final reader = await source.open();
    late final List<int> head;
    try {
      head = await reader.read(16);
    } finally {
      await reader.close();
    }
    bool starts(List<int> bytes) =>
        head.length >= bytes.length &&
        List.generate(
          bytes.length,
          (i) => head[i] == bytes[i],
        ).every((same) => same);
    bool asciiAt(int offset, String value) =>
        head.length >= offset + value.length &&
        List.generate(
          value.length,
          (i) => head[offset + i] == value.codeUnitAt(i),
        ).every((same) => same);

    switch (p.extension(name).toLowerCase()) {
      case '.png':
        return starts([0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10])
            ? 'image/png'
            : null;
      case '.jpg':
      case '.jpeg':
        return starts([0xff, 0xd8, 0xff]) ? 'image/jpeg' : null;
      case '.gif':
        return asciiAt(0, 'GIF87a') || asciiAt(0, 'GIF89a')
            ? 'image/gif'
            : null;
      case '.webp':
        return asciiAt(0, 'RIFF') && asciiAt(8, 'WEBP') ? 'image/webp' : null;
      case '.mp3':
        return asciiAt(0, 'ID3') ||
                (head.length >= 2 &&
                    head[0] == 0xff &&
                    (head[1] & 0xe0) == 0xe0)
            ? 'audio/mpeg'
            : null;
      case '.wav':
        return asciiAt(0, 'RIFF') && asciiAt(8, 'WAVE') ? 'audio/wav' : null;
      case '.ogg':
        return asciiAt(0, 'OggS') ? 'audio/ogg' : null;
      case '.m4a':
        return asciiAt(4, 'ftyp') ? 'audio/mp4' : null;
      default:
        return null;
    }
  }
}
