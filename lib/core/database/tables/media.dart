import 'package:drift/drift.dart';

@DataClassName('StoredMedia')
class Media extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get contentHash => text().unique()();
  TextColumn get originalName => text()();
  TextColumn get relativePath => text()();
  TextColumn get mimeType => text()();
  IntColumn get byteLength => integer()();
  IntColumn get referenceCount => integer().withDefault(const Constant(0))();
  IntColumn get createdAtUtc => integer()();
}
