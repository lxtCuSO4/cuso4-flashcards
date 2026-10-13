import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:cuso4_flashcards/features/import/data/apkg_archive_reader.dart';
import 'package:cuso4_flashcards/features/import/domain/import_error.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory scratch;
  final reader = ApkgArchiveReader();

  setUp(
    () async => scratch = await Directory.systemTemp.createTemp('apkg_test_'),
  );
  tearDown(() async => scratch.delete(recursive: true));

  Future<File> packageWith(List<ArchiveFile> entries) async {
    final archive = Archive()
      ..addFile(ArchiveFile.string('collection.anki2', 'db'));
    for (final entry in entries) {
      archive.addFile(entry);
    }
    final file = File('${scratch.path}${Platform.pathSeparator}deck.apkg');
    await file.writeAsBytes(ZipEncoder().encodeBytes(archive));
    return file;
  }

  test(
    'extracts a legacy collection and maps media by original name',
    () async {
      final file = await packageWith([
        ArchiveFile.string('media', jsonEncode({'0': 'image.png'})),
        ArchiveFile.bytes('0', [0x89, 0x50, 0x4e, 0x47]),
      ]);
      final result = await reader.extract(file, destination: scratch);
      try {
        expect(await result.collectionPath.readAsString(), 'db');
        expect(await result.mediaFiles['image.png']!.readAsBytes(), [
          0x89,
          0x50,
          0x4e,
          0x47,
        ]);
      } finally {
        await result.dispose();
      }
      expect(await result.root.exists(), isFalse);
    },
  );

  test('rejects traversal paths', () async {
    final file = await packageWith([ArchiveFile.string('../escape', 'bad')]);
    await expectLater(
      reader.extract(file, destination: scratch),
      throwsA(
        isA<ApkgImportException>().having(
          (e) => e.code,
          'code',
          ImportErrorCode.damagedArchive,
        ),
      ),
    );
  });

  test('rejects duplicate paths in the archive', () async {
    final file = await packageWith([
      ArchiveFile.string('sub\\item', 'a'),
      ArchiveFile.string('sub/item', 'b'),
    ]);
    await expectLater(
      reader.extract(file, destination: scratch),
      throwsA(
        isA<ApkgImportException>().having(
          (e) => e.message,
          'message',
          '牌组包包含重复文件或符号链接。',
        ),
      ),
    );
  });

  test('rejects corrupted stored content using CRC', () async {
    const marker = 'unique-content-marker';
    final file = await packageWith([
      ArchiveFile.noCompress('0', marker.length, utf8.encode(marker)),
    ]);
    final bytes = await file.readAsBytes();
    final first = bytes.indexOf(utf8.encode(marker).first);
    expect(first, greaterThanOrEqualTo(0));
    bytes[first] ^= 0x01;
    await file.writeAsBytes(bytes);
    await expectLater(
      reader.extract(file, destination: scratch),
      throwsA(
        isA<ApkgImportException>().having(
          (e) => e.code,
          'code',
          ImportErrorCode.damagedArchive,
        ),
      ),
    );
  });

  test(
    'rejects current collection format instead of reading a compatibility stub',
    () async {
      final file = await packageWith([
        ArchiveFile.string('collection.anki21b', 'new'),
      ]);
      await expectLater(
        reader.extract(file, destination: scratch),
        throwsA(
          isA<ApkgImportException>().having(
            (e) => e.code,
            'code',
            ImportErrorCode.unsupportedCollectionVersion,
          ),
        ),
      );
    },
  );

  test('reports a non-ZIP apkg as a damaged archive', () async {
    final file = File('${scratch.path}${Platform.pathSeparator}not-zip.apkg');
    await file.writeAsString('not a ZIP');
    await expectLater(
      reader.extract(file, destination: scratch),
      throwsA(
        isA<ApkgImportException>().having(
          (e) => e.code,
          'code',
          ImportErrorCode.damagedArchive,
        ),
      ),
    );
  });

  test(
    'rejects an archive whose inflated data exceeds the configured limit',
    () async {
      final file = await packageWith([ArchiveFile.string('0', 'x' * 1024)]);
      await expectLater(
        ApkgArchiveReader(maxExtractedBytes: 128)
            .extract(file, destination: scratch),
        throwsA(
          isA<ApkgImportException>().having(
            (e) => e.code,
            'code',
            ImportErrorCode.invalidArchive,
          ),
        ),
      );
    },
  );
}
