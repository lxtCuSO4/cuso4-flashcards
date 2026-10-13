import 'package:drift/drift.dart';

import 'cards.dart';

@DataClassName('StoredReviewLog')
@TableIndex(name: 'reviews_time', columns: {#reviewedAtUtc})
class ReviewLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get cardId =>
      integer().references(Cards, #id, onDelete: KeyAction.cascade)();
  IntColumn get reviewedAtUtc => integer()();
  IntColumn get rating => integer()();
  IntColumn get elapsedMilliseconds => integer()();
  TextColumn get beforeStateJson => text()();
  TextColumn get afterStateJson => text()();
  TextColumn get source => text().withDefault(const Constant('study'))();
}
