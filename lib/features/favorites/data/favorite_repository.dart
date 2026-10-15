import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:html/parser.dart' as html;

import '../../../core/database/app_database.dart';
import '../../decks/domain/cloze_parser.dart';
import '../../decks/domain/note.dart';

class FavoriteEntry {
  const FavoriteEntry({
    required this.cardId,
    required this.deckName,
    required this.preview,
    required this.type,
    required this.clozeIndex,
  });
  final int cardId;
  final String deckName;
  final String preview;
  final NoteType type;
  final int clozeIndex;
}

class FavoritePage {
  FavoritePage({required Iterable<FavoriteEntry> items, required this.hasNext})
    : items = List.unmodifiable(items);
  final List<FavoriteEntry> items;
  final bool hasNext;
}

class FavoriteRepository {
  FavoriteRepository(this.db);
  final AppDatabase db;

  Stream<FavoritePage> watchPage({
    int limit = 30,
    int offset = 0,
    int? deckId,
    bool includeChildren = true,
  }) {
    if (limit < 1 || limit > 30 || offset < 0) {
      throw ArgumentError('收藏分页大小须为 1–30，偏移不能为负数');
    }
    final query = db.customSelect(
      '''WITH RECURSIVE scope(id) AS (
        SELECT id FROM decks WHERE id = ?
        UNION
        SELECT d.id FROM decks d JOIN scope s ON d.parent_id = s.id WHERE ? = 1
      )
      SELECT c.id AS card_id, c.cloze_index, n.fields_json, n.note_type,
        d.name AS deck_name
      FROM favorites f JOIN cards c ON c.id = f.card_id
      JOIN notes n ON n.id = c.note_id JOIN decks d ON d.id = n.deck_id
      WHERE (? IS NULL OR n.deck_id IN (SELECT id FROM scope))
      ORDER BY f.created_at_utc DESC, c.id DESC LIMIT ? OFFSET ?''',
      variables: [
        Variable<int>(deckId),
        Variable(includeChildren ? 1 : 0),
        Variable<int>(deckId),
        Variable(limit + 1),
        Variable(offset),
      ],
      readsFrom: {db.favorites, db.cards, db.notes, db.decks},
    );
    return query.watch().map(
      (rows) => FavoritePage(
        hasNext: rows.length > limit,
        items: rows.take(limit).map((row) {
          final clozeIndex = row.read<int>('cloze_index');
          final fields = Map<String, String>.from(
            jsonDecode(row.read<String>('fields_json')) as Map,
          );
          final type = NoteType.values[row.read<int>('note_type')];
          final question = type != NoteType.cloze
              ? fields['front'] ?? ''
              : ClozeParser().renderQuestion(fields['text'] ?? '', clozeIndex);
          final fragment = html.parseFragment(question);
          for (final blocked in fragment.querySelectorAll('script,style')) {
            blocked.remove();
          }
          final preview = (fragment.text ?? '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          return FavoriteEntry(
            cardId: row.read<int>('card_id'),
            deckName: row.read<String>('deck_name'),
            preview: preview.isEmpty ? '图片或媒体卡片' : preview,
            type: type,
            clozeIndex: clozeIndex,
          );
        }),
      ),
    );
  }
}
