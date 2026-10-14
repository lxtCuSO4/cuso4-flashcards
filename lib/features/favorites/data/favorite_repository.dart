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

  Stream<FavoritePage> watchPage({int limit = 30, int offset = 0}) {
    if (limit < 1 || limit > 30 || offset < 0) {
      throw ArgumentError('收藏分页大小须为 1–30，偏移不能为负数');
    }
    final query =
        db.select(db.favorites).join([
            innerJoin(db.cards, db.cards.id.equalsExp(db.favorites.cardId)),
            innerJoin(db.notes, db.notes.id.equalsExp(db.cards.noteId)),
            innerJoin(db.decks, db.decks.id.equalsExp(db.notes.deckId)),
          ])
          ..orderBy([
            OrderingTerm.desc(db.favorites.createdAtUtc),
            OrderingTerm.desc(db.cards.id),
          ])
          ..limit(limit + 1, offset: offset);
    return query.watch().map(
      (rows) => FavoritePage(
        hasNext: rows.length > limit,
        items: rows.take(limit).map((row) {
          final card = row.readTable(db.cards);
          final note = row.readTable(db.notes);
          final fields = Map<String, String>.from(
            jsonDecode(note.fieldsJson) as Map,
          );
          final type = NoteType.values[note.noteType];
          final question = type == NoteType.basic
              ? fields['front'] ?? ''
              : ClozeParser().renderQuestion(
                  fields['text'] ?? '',
                  card.clozeIndex,
                );
          final fragment = html.parseFragment(question);
          for (final blocked in fragment.querySelectorAll('script,style')) {
            blocked.remove();
          }
          final preview = (fragment.text ?? '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          return FavoriteEntry(
            cardId: card.id,
            deckName: row.readTable(db.decks).name,
            preview: preview.isEmpty ? '图片或媒体卡片' : preview,
            type: type,
            clozeIndex: card.clozeIndex,
          );
        }),
      ),
    );
  }
}
