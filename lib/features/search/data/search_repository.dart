import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:html/parser.dart' as html;

import '../../../core/database/app_database.dart';
import '../../decks/data/note_repository.dart';
import '../../decks/domain/cloze_parser.dart';

typedef SearchQuery = ({
  String text,
  int? deckId,
  bool includeChildren,
  int? noteType,
  String? tag,
  bool favoritesOnly,
  int offset,
});

enum BatchAction { move, addTags, removeTags, delete }

class SearchItem {
  SearchItem(
    this.id,
    this.deckId,
    this.deckPath,
    this.noteType,
    this.fields,
    this.cardCount,
  );
  final int id, deckId, noteType, cardCount;
  final String deckPath;
  final Map<String, String> fields;
  String get summary {
    final source = fields['front'] ?? fields['text'] ?? '';
    final text =
        html.parseFragment(ClozeParser().renderAnswer(source, 0)).text ?? '';
    final trimmed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return trimmed.isEmpty ? '（图片或空白内容）' : trimmed;
  }
}

class SearchPageResult {
  SearchPageResult(List<SearchItem> items)
    : hasNext = items.length > 30,
      items = List.unmodifiable(items.take(30));
  final List<SearchItem> items;
  final bool hasNext;
}

class SearchRepository {
  SearchRepository(this.db, this.notes);
  final AppDatabase db;
  final NoteRepository notes;

  Stream<SearchPageResult> watch(SearchQuery query) {
    final where = <String>[];
    final variables = <Variable>[];
    final scope = query.deckId == null
        ? ''
        : '''scope(id) AS (
      SELECT id FROM decks WHERE id = ?
      ${query.includeChildren ? 'UNION SELECT d.id FROM decks d JOIN scope s ON d.parent_id = s.id' : ''}),''';
    if (query.deckId != null) {
      variables.add(Variable(query.deckId!));
      where.add('n.deck_id IN (SELECT id FROM scope)');
    }
    if (query.text.trim().isNotEmpty) {
      where.add(
        'EXISTS (SELECT 1 FROM json_each(n.fields_json) f WHERE instr(lower(CAST(f.value AS TEXT)), lower(?)) > 0)',
      );
      variables.add(Variable(query.text.trim()));
    }
    if (query.noteType != null) {
      where.add('n.note_type = ?');
      variables.add(Variable(query.noteType!));
    }
    if (query.tag != null) {
      where.add(
        'EXISTS (SELECT 1 FROM note_tags nt JOIN tags t ON t.id = nt.tag_id WHERE nt.note_id = n.id AND t.name = ?)',
      );
      variables.add(Variable(query.tag!));
    }
    if (query.favoritesOnly) {
      where.add(
        'EXISTS (SELECT 1 FROM cards c JOIN favorites f ON f.card_id = c.id WHERE c.note_id = n.id)',
      );
    }
    variables.add(Variable(query.offset.clamp(0, 100000000)));
    return db
        .customSelect(
          '''WITH RECURSIVE $scope paths(id, path) AS (
      SELECT id, name FROM decks WHERE parent_id IS NULL
      UNION ALL SELECT d.id, p.path || ' / ' || d.name FROM decks d JOIN paths p ON d.parent_id = p.id)
      SELECT n.id, n.deck_id, n.note_type, n.fields_json, p.path,
      (SELECT COUNT(*) FROM cards c WHERE c.note_id = n.id) AS card_count
      FROM notes n JOIN paths p ON p.id = n.deck_id
      ${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'}
      ORDER BY n.id LIMIT 31 OFFSET ?''',
          variables: variables,
          readsFrom: {
            db.notes,
            db.decks,
            db.cards,
            db.tags,
            db.noteTags,
            db.favorites,
          },
        )
        .watch()
        .map(
          (rows) => SearchPageResult(
            rows
                .map(
                  (row) => SearchItem(
                    row.read<int>('id'),
                    row.read<int>('deck_id'),
                    row.read<String>('path'),
                    row.read<int>('note_type'),
                    Map<String, String>.from(
                      jsonDecode(row.read<String>('fields_json')) as Map,
                    ),
                    row.read<int>('card_count'),
                  ),
                )
                .toList(),
          ),
        );
  }

  Future<void> applyBatch(
    Set<int> ids, {
    required BatchAction action,
    int? deckId,
    Iterable<String> tags = const [],
  }) async {
    final selected = Set<int>.of(ids);
    if (selected.isEmpty || selected.length > 500) {
      throw ArgumentError('每次请选择 1–500 条笔记。');
    }
    final names = tags.map((v) => v.trim()).where((v) => v.isNotEmpty).toSet();
    if ((action == BatchAction.addTags || action == BatchAction.removeTags) &&
        (names.isEmpty ||
            names.any((n) => n.length > 255 || RegExp(r'\s').hasMatch(n)))) {
      throw ArgumentError('请填写标签，每个标签最多 255 字且不包含空格。');
    }
    await db.transaction(() async {
      final existing = await (db.select(
        db.notes,
      )..where((n) => n.id.isIn(selected))).get();
      if (existing.length != selected.length) {
        throw StateError('部分笔记已删除，请刷新后重新选择。');
      }
      if (action == BatchAction.move) {
        if (deckId == null ||
            await (db.select(
                  db.decks,
                )..where((d) => d.id.equals(deckId))).getSingleOrNull() ==
                null) {
          throw ArgumentError('目标牌组不存在，请重新选择。');
        }
        await (db.update(db.notes)..where((n) => n.id.isIn(selected))).write(
          NotesCompanion(
            deckId: Value(deckId),
            modifiedAtUtc: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
          ),
        );
      } else if (action == BatchAction.delete) {
        for (final id in selected) {
          await notes.deleteNote(id);
        }
      } else {
        for (final name in names) {
          if (action == BatchAction.addTags) {
            await db
                .into(db.tags)
                .insert(
                  TagsCompanion.insert(name: name),
                  mode: InsertMode.insertOrIgnore,
                );
          }
          final tag = await (db.select(
            db.tags,
          )..where((t) => t.name.equals(name))).getSingleOrNull();
          if (tag == null) continue;
          if (action == BatchAction.addTags) {
            for (final id in selected) {
              await db
                  .into(db.noteTags)
                  .insert(
                    NoteTagsCompanion.insert(noteId: id, tagId: tag.id),
                    mode: InsertMode.insertOrIgnore,
                  );
            }
          } else {
            await (db.delete(db.noteTags)..where(
                  (t) => t.noteId.isIn(selected) & t.tagId.equals(tag.id),
                ))
                .go();
          }
        }
      }
    });
  }
}
