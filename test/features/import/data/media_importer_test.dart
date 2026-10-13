import 'dart:io';

import 'package:cuso4_flashcards/features/import/data/media_importer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory scratch;
  late Directory target;

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('media_import_test_');
    target = Directory('${scratch.path}${Platform.pathSeparator}private_media');
  });
  tearDown(() async => scratch.delete(recursive: true));

  Future<File> image(String name, List<int> bytes) async {
    final file = File('${scratch.path}${Platform.pathSeparator}$name');
    await file.writeAsBytes(bytes);
    return file;
  }

  test(
    'deduplicates identical content and tracks missing references',
    () async {
      final bytes = [0x89, 0x50, 0x4e, 0x47, 13, 10, 26, 10, 0, 1];
      final first = await image('source-1', bytes);
      final second = await image('source-2', bytes);
      final prepared = await MediaImporter(target).prepare(
        {'a.png': first, 'b.png': second},
        {'a.png', 'b.png', 'gone.png'},
      );
      expect(prepared.missingNames, {'gone.png'});
      expect(prepared.assetsByName.keys, {'a.png', 'b.png'});
      expect(
        prepared.assetsByName['a.png']!.contentHash,
        prepared.assetsByName['b.png']!.contentHash,
      );
      expect(await prepared.commit(), 1);
      final path = prepared.assetsByName['a.png']!.relativePath;
      expect(
        await File('${target.path}${Platform.pathSeparator}$path')
            .readAsBytes(),
        bytes,
      );
      await prepared.complete();
      expect(
        await File('${target.path}${Platform.pathSeparator}$path').exists(),
        isTrue,
      );
    },
  );

  test('rollback removes newly committed files and staging data', () async {
    final source = await image('source', [
      0x89,
      0x50,
      0x4e,
      0x47,
      13,
      10,
      26,
      10,
    ]);
    final prepared = await MediaImporter(target)
        .prepare({'a.png': source}, {'a.png'});
    await prepared.commit();
    final path = prepared.assetsByName['a.png']!.relativePath;
    await prepared.rollback();
    expect(
      await File('${target.path}${Platform.pathSeparator}$path').exists(),
      isFalse,
    );
    expect(await prepared.stagingDirectory.exists(), isFalse);
  });

  test(
    'rejects files whose signature does not match an allowed media type',
    () async {
      final source = await image('source', [1, 2, 3, 4]);
      final prepared = await MediaImporter(target)
          .prepare({'a.png': source}, {'a.png'});
      expect(prepared.assetsByName, isEmpty);
      expect(prepared.unsupportedNames, {'a.png'});
      await prepared.complete();
    },
  );
}
