import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../../../core/database/app_database.dart';

class DatabaseSnapshotService {
  /// VACUUM INTO includes committed WAL pages; copying the live main file does not.
  static Future<void> create(AppDatabase db, File destination) async {
    await destination.parent.create(recursive: true);
    await db.customStatement('VACUUM INTO ?', [destination.path]);
  }

  static void fromRecovery(String source, String destination) {
    final db = sqlite3.open(source, mode: OpenMode.readOnly);
    try {
      db.execute('VACUUM INTO ?', [destination]);
    } finally {
      db.close();
    }
  }
}
