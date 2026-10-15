import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/import_recovery_notice.dart';

class ImportRecoveryRepository {
  ImportRecoveryRepository(this.db);
  final AppDatabase db;

  Stream<ImportRecoveryNotice?> watch() =>
      (db.select(db.appSettings)
            ..where((s) => s.key.equals(ImportRecoveryNotice.settingKey)))
          .watchSingleOrNull()
          .map(
            (row) =>
                row == null ? null : ImportRecoveryNotice.parse(row.valueJson),
          );

  Future<void> acknowledge(ImportRecoveryNotice notice) async {
    await (db.delete(db.appSettings)..where(
          (s) =>
              s.key.equals(ImportRecoveryNotice.settingKey) &
              s.valueJson.equals(notice.raw),
        ))
        .go();
  }
}
