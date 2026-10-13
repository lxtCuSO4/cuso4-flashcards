import 'package:drift/drift.dart';

import 'decks.dart';

@DataClassName('StoredNote')
@TableIndex(name: 'notes_deck', columns: {#deckId})
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get deckId =>
      integer().references(Decks, #id, onDelete: KeyAction.cascade)();
  IntColumn get noteType => integer()();
  TextColumn get fieldsJson => text()();
  IntColumn get createdAtUtc => integer()();
  IntColumn get modifiedAtUtc => integer()();
}
