import 'package:drift/drift.dart';

class ImportJobs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sourceName => text()();
  TextColumn get status => text()();
  TextColumn get reportJson => text().nullable()();
  IntColumn get createdAtUtc => integer()();
  IntColumn get modifiedAtUtc => integer()();
}

class ImportJobErrors extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get jobId =>
      integer().references(ImportJobs, #id, onDelete: KeyAction.cascade)();
  TextColumn get reason => text()();
  IntColumn get count => integer()();
}
