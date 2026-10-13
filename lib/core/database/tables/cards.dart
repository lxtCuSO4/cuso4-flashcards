import 'package:drift/drift.dart';

import 'notes.dart';

@DataClassName('StoredCard')
@TableIndex(name: 'cards_due', columns: {#dueAtUtc, #state})
class Cards extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get noteId =>
      integer().references(Notes, #id, onDelete: KeyAction.cascade)();

  /// Zero denotes a basic card; positive numbers denote Cloze indexes.
  IntColumn get clozeIndex => integer().withDefault(const Constant(0))();
  IntColumn get dueAtUtc => integer()();
  IntColumn get state => integer().withDefault(const Constant(0))();
  RealColumn get stability => real().nullable()();
  RealColumn get difficulty => real().nullable()();
  IntColumn get learningStep => integer().withDefault(const Constant(0))();
  IntColumn get repetitions => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  IntColumn get lastReviewAtUtc => integer().nullable()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {noteId, clozeIndex},
  ];
}

@DataClassName('StoredFavorite')
class Favorites extends Table {
  IntColumn get cardId =>
      integer().references(Cards, #id, onDelete: KeyAction.cascade)();
  IntColumn get createdAtUtc => integer()();
  @override
  Set<Column> get primaryKey => {cardId};
}
