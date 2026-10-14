import 'dart:io';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/media/media_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late AppDatabase db;
  late Directory root;
  late MediaRepository repository;
  final hash = 'a' * 64;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final parent = Directory(
      p.join(Directory.current.path, 'build', 'test_media'),
    );
    await parent.create(recursive: true);
    root = await parent.createTemp('resolution_');
    repository = MediaRepository(db, directory: root);
    await db
        .into(db.media)
        .insert(
          MediaCompanion.insert(
            contentHash: hash,
            originalName: 'image.png',
            relativePath: hash,
            mimeType: 'image/png',
            byteLength: 3,
            createdAtUtc: 0,
          ),
        );
    await File(p.join(root.path, hash)).writeAsBytes([1, 2, 3]);
  });
  tearDown(() async {
    await db.close();
    await root.delete(recursive: true);
  });

  test('resolves only known local media of the requested kind', () async {
    final asset = await repository.resolve(
      'media:$hash',
      kind: MediaKind.image,
    );
    expect(asset?.file.path, p.join(await root.resolveSymbolicLinks(), hash));
    expect(asset?.mimeType, 'image/png');
    expect(
      await repository.resolve('media:$hash', kind: MediaKind.audio),
      isNull,
    );
    for (final token in [
      'https://example.com/a.png',
      '../a.png',
      'media:${'b' * 64}',
    ]) {
      expect(await repository.resolve(token, kind: MediaKind.image), isNull);
    }
  });

  test(
    'refuses stored traversal paths and missing or truncated files',
    () async {
      await db.customStatement('UPDATE media SET relative_path = ?', [
        '../outside',
      ]);
      expect(
        await repository.resolve('media:$hash', kind: MediaKind.image),
        isNull,
      );
      await db.customStatement('UPDATE media SET relative_path = ?', [hash]);
      await File(p.join(root.path, hash)).writeAsBytes([1]);
      expect(
        await repository.resolve('media:$hash', kind: MediaKind.image),
        isNull,
      );
      await File(p.join(root.path, hash)).delete();
      expect(
        await repository.resolve('media:$hash', kind: MediaKind.image),
        isNull,
      );
    },
  );
}
