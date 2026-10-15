import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class PracticeRound {
  PracticeRound({required this.deckName, required Iterable<int> cardIds})
    : cardIds = List.unmodifiable(cardIds);

  final String deckName;
  final List<int> cardIds;
}

/// Independent of the formal learning queue: this feature only reads data.
class PracticeRepository {
  PracticeRepository(this.db);
  final AppDatabase db;
  static const maxCount = 500;

  Future<PracticeRound> sample({
    required int deckId,
    required bool includeChildren,
    required int count,
  }) async {
    if (count < 1 || count > maxCount) {
      throw ArgumentError('练习张数须为 1–500');
    }
    return db.transaction(() async {
      final deck = await (db.select(
        db.decks,
      )..where((d) => d.id.equals(deckId))).getSingleOrNull();
      if (deck == null) throw StateError('牌组不存在，请返回牌组列表');
      final rows = await db
          .customSelect(
            '''WITH RECURSIVE scope(id) AS (
          SELECT id FROM decks WHERE id = ?
          UNION
          SELECT d.id FROM decks d JOIN scope s ON d.parent_id = s.id WHERE ? = 1
        )
        SELECT c.id FROM cards c JOIN notes n ON n.id = c.note_id
        WHERE n.deck_id IN (SELECT id FROM scope)
        ORDER BY RANDOM() LIMIT ?''',
            variables: [
              Variable(deckId),
              Variable(includeChildren ? 1 : 0),
              Variable(count),
            ],
            readsFrom: {db.decks, db.notes, db.cards},
          )
          .get();
      return PracticeRound(
        deckName: deck.name,
        cardIds: rows.map((r) => r.read<int>('id')),
      );
    });
  }
}
