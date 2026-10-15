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
    int? deckId,
    required bool includeChildren,
    required int count,
    bool favoritesOnly = false,
  }) async {
    if (count < 1 || count > maxCount) {
      throw ArgumentError('练习张数须为 1–500');
    }
    if (deckId == null && !favoritesOnly) {
      throw ArgumentError('请选择练习牌组');
    }
    return db.transaction(() async {
      final deck = deckId == null
          ? null
          : await (db.select(
              db.decks,
            )..where((d) => d.id.equals(deckId))).getSingleOrNull();
      if (deckId != null && deck == null) throw StateError('牌组不存在，请返回牌组列表');
      final rows = await db
          .customSelect(
            '''WITH RECURSIVE scope(id) AS (
          SELECT id FROM decks WHERE id = ?
          UNION
          SELECT d.id FROM decks d JOIN scope s ON d.parent_id = s.id WHERE ? = 1
        )
        SELECT c.id FROM cards c JOIN notes n ON n.id = c.note_id
        WHERE (? IS NULL OR n.deck_id IN (SELECT id FROM scope))
          AND (? = 0 OR EXISTS (SELECT 1 FROM favorites f WHERE f.card_id = c.id))
        ORDER BY RANDOM() LIMIT ?''',
            variables: [
              Variable<int>(deckId),
              Variable(includeChildren ? 1 : 0),
              Variable<int>(deckId),
              Variable(favoritesOnly ? 1 : 0),
              Variable(count),
            ],
            readsFrom: {db.decks, db.notes, db.cards, db.favorites},
          )
          .get();
      return PracticeRound(
        deckName: deck?.name ?? '全部牌组',
        cardIds: rows.map((r) => r.read<int>('id')),
      );
    });
  }
}
