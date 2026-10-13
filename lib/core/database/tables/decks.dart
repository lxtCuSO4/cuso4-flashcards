import 'package:drift/drift.dart';

@DataClassName('StoredDeck')
class Decks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get parentId => integer().nullable().references(
    Decks,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get name => text().withLength(min: 1, max: 255)();
  IntColumn get createdAtUtc => integer()();
  IntColumn get modifiedAtUtc => integer()();
}
