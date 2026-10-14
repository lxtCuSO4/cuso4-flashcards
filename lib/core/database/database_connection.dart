import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/backup/data/restore_service.dart';

QueryExecutor openLocalDatabase() => LazyDatabase(() async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  RestoreService.recoverInterrupted(directory);
  return NativeDatabase.createInBackground(
    File(p.join(directory.path, 'cuso4.sqlite')),
    setup: (database) => database.execute('PRAGMA journal_mode = WAL'),
  );
});
