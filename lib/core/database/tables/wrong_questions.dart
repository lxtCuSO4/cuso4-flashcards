import 'package:drift/drift.dart';

import 'cards.dart';

@DataClassName('StoredWrongQuestion')
class WrongQuestions extends Table {
  IntColumn get cardId =>
      integer().references(Cards, #id, onDelete: KeyAction.cascade)();
  IntColumn get wrongCount => integer()();
  IntColumn get lastWrongAtUtc => integer()();

  @override
  Set<Column> get primaryKey => {cardId};
}
