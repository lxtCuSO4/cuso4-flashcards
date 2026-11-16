import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';

class RecitationRound {
  const RecitationRound({
    required this.noteIds,
    required this.cardIds,
    required this.index,
    required this.includeChildren,
    required this.random,
  });
  final List<int> noteIds;
  final List<int> cardIds;
  final int index;
  final bool includeChildren;
  final bool random;
}

/// Reading positions are separate from cards, review logs and daily quotas.
class RecitationRepository {
  RecitationRepository(this.db);
  final AppDatabase db;
  String _key(int deckId) => 'recitation:$deckId';

  Future<RecitationRound> open(
    int deckId, {
    bool? includeChildren,
    bool? random,
  }) async {
    final deck = await (db.select(
      db.decks,
    )..where((d) => d.id.equals(deckId))).getSingleOrNull();
    if (deck == null) throw StateError('牌组不存在，请返回牌组列表。');
    final setting = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(_key(deckId)))).getSingleOrNull();
    final saved = setting == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(setting.valueJson) as Map);
    final children =
        includeChildren ??
        (saved['includeChildren'] == true ||
            !saved.containsKey('includeChildren'));
    final shuffled = random ?? (saved['random'] == true);
    final rows = await db
        .customSelect(
          '''
      WITH RECURSIVE scope(id, path) AS (
        SELECT id, name FROM decks WHERE id = ?
        UNION ALL
        SELECT d.id, s.path || char(31) || d.name FROM decks d JOIN scope s ON d.parent_id = s.id WHERE ? = 1
      )
      SELECT n.id AS note_id, MIN(c.id) AS card_id
      FROM notes n JOIN scope s ON s.id = n.deck_id JOIN cards c ON c.note_id = n.id
      GROUP BY n.id, s.path ORDER BY s.path, n.id
    ''',
          variables: [Variable(deckId), Variable(children ? 1 : 0)],
          readsFrom: {db.decks, db.notes, db.cards},
        )
        .get();
    final cards = {
      for (final row in rows)
        row.read<int>('note_id'): row.read<int>('card_id'),
    };
    var ids = cards.keys.toList();
    if (shuffled) {
      final savedOrder = saved['order'];
      if (saved['random'] == true &&
          savedOrder is List &&
          savedOrder.every((v) => v is int)) {
        final used = <int>{};
        final kept = savedOrder
            .cast<int>()
            .where((id) => cards.containsKey(id) && used.add(id))
            .toList();
        final added = ids.where((id) => !used.contains(id)).toList()
          ..shuffle(Random());
        ids = [...kept, ...added];
      } else {
        ids.shuffle(Random());
      }
    }
    final savedNoteId = saved['noteId'];
    final index = savedNoteId is int ? ids.indexOf(savedNoteId) : -1;
    return RecitationRound(
      noteIds: List.unmodifiable(ids),
      cardIds: List.unmodifiable(ids.map((id) => cards[id]!)),
      index: index < 0 ? 0 : index,
      includeChildren: children,
      random: shuffled,
    );
  }

  Future<void> savePosition(
    int deckId,
    RecitationRound round,
    int index,
  ) async {
    if (round.noteIds.isNotEmpty &&
        (index < 0 || index >= round.noteIds.length)) {
      return;
    }
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: _key(deckId),
            valueJson: jsonEncode({
              'version': 1,
              'includeChildren': round.includeChildren,
              'random': round.random,
              'noteId': round.noteIds.isEmpty ? null : round.noteIds[index],
              if (round.random) 'order': round.noteIds,
            }),
          ),
        );
  }
}
