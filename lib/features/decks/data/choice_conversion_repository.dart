import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/media/media_repository.dart';
import '../domain/choice_question.dart';
import '../domain/choice_recognizer.dart';
import '../domain/note.dart';

class ChoiceConversionPreview {
  ChoiceConversionPreview._(
    this.deckId,
    List<_ConversionEntry> entries,
    this.retainedBasic,
  ) : _entries = List.unmodifiable(entries);
  final int deckId;
  final int retainedBasic;
  final List<_ConversionEntry> _entries;
  int get total => _entries.length;
  int get singleChoice =>
      _entries.where((e) => e.question.type == NoteType.singleChoice).length;
  int get multipleChoice => total - singleChoice;
}

class _ConversionEntry {
  const _ConversionEntry(this.before, this.cardId, this.question);
  final StoredNote before;
  final int cardId;
  final ChoiceQuestion question;
}

/// Converts note content only. Card IDs, scheduling and related rows stay intact.
class ChoiceConversionRepository {
  ChoiceConversionRepository(this.db, {MediaRepository? mediaRepository})
    : media = mediaRepository ?? MediaRepository(db);
  final AppDatabase db;
  final MediaRepository media;
  final _recognizer = ChoiceRecognizer();

  Future<ChoiceConversionPreview> scan(int deckId) => db.transaction(() async {
    final ids = await _deckIds(deckId);
    final notes =
        await (db.select(db.notes)..where(
              (n) =>
                  n.deckId.isIn(ids) & n.noteType.equals(NoteType.basic.index),
            ))
            .get();
    final entries = <_ConversionEntry>[];
    for (final note in notes) {
      final fields = media.fieldsFromJson(note.fieldsJson);
      final question = _recognizer
          .recognize(fields['front'] ?? '', fields['back'] ?? '')
          .question;
      if (question == null) continue;
      final cards = await (db.select(
        db.cards,
      )..where((c) => c.noteId.equals(note.id))).get();
      if (cards.length != 1 || cards.single.clozeIndex != 0) continue;
      entries.add(_ConversionEntry(note, cards.single.id, question));
    }
    return ChoiceConversionPreview._(
      deckId,
      entries,
      notes.length - entries.length,
    );
  });

  Future<int> apply(ChoiceConversionPreview preview) =>
      db.transaction(() async {
        final ids = await _deckIds(preview.deckId);
        // Validate the entire preview before any write; a stale batch is never partial.
        for (final entry in preview._entries) {
          final current = await (db.select(
            db.notes,
          )..where((n) => n.id.equals(entry.before.id))).getSingleOrNull();
          final cards = await (db.select(
            db.cards,
          )..where((c) => c.noteId.equals(entry.before.id))).get();
          if (current != entry.before ||
              !ids.contains(entry.before.deckId) ||
              cards.length != 1 ||
              cards.single.id != entry.cardId ||
              cards.single.clozeIndex != 0) {
            throw StateError('卡片在扫描后已发生变化，本次未转换任何卡片，请重新扫描。');
          }
        }
        final now = DateTime.now().toUtc().millisecondsSinceEpoch;
        for (final entry in preview._entries) {
          final before = media.fieldsFromJson(entry.before.fieldsJson);
          final after = {...before, ...entry.question.toFields()};
          await (db.update(
            db.notes,
          )..where((n) => n.id.equals(entry.before.id))).write(
            NotesCompanion(
              noteType: Value(entry.question.type.index),
              fieldsJson: Value(jsonEncode(after)),
              modifiedAtUtc: Value(now),
            ),
          );
          await media.replaceReferences(before, after);
        }
        return preview.total;
      });

  Future<Set<int>> _deckIds(int root) async {
    final decks = await db.select(db.decks).get();
    if (!decks.any((d) => d.id == root)) throw StateError('牌组已不存在，请返回牌组列表。');
    final children = <int, List<int>>{};
    for (final deck in decks) {
      if (deck.parentId != null) {
        children.putIfAbsent(deck.parentId!, () => []).add(deck.id);
      }
    }
    final result = <int>{};
    final pending = [root];
    while (pending.isNotEmpty) {
      final id = pending.removeLast();
      if (result.add(id)) pending.addAll(children[id] ?? const []);
    }
    return result;
  }
}
