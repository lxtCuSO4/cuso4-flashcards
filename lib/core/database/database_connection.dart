import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../features/backup/data/restore_service.dart';
import '../recovery/import_recovery.dart';

QueryExecutor openLocalDatabase({Directory? root}) => LazyDatabase(() async {
  final directory = root ?? await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  RestoreService.recoverInterrupted(directory);
  return NativeDatabase.createInBackground(
    File(p.join(directory.path, 'cuso4.sqlite')),
    setup: (database) {
      database.execute('PRAGMA journal_mode = WAL');
      ImportRecovery(directory).run(database);
    },
  );
});
