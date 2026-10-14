import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/media/media_repository.dart';
import '../domain/cloze_parser.dart';
import '../domain/note.dart';

class ClozeRemovalConfirmation implements Exception {
  ClozeRemovalConfirmation(Iterable<int> indexes)
    : indexes = List.unmodifiable(indexes);
  final List<int> indexes;

  @override
  String toString() => '修改将删除填空卡 ${indexes.join('、')}，请确认后继续。';
}

class NoteRepository {
  NoteRepository(this.db, {MediaRepository? mediaRepository})
    : media = mediaRepository ?? MediaRepository(db);
  final AppDatabase db;
  final MediaRepository media;
  final _cloze = ClozeParser();

  Future<int> createBasicNote({
    required int deckId,
    required String front,
    String back = '',
    Iterable<String> tags = const [],
  }) => _create(deckId, NoteType.basic, {'front': front, 'back': back}, tags);

  Future<int> createClozeNote({
    required int deckId,
    required String text,
    String extra = '',
    Iterable<String> tags = const [],
  }) => _create(deckId, NoteType.cloze, {'text': text, 'extra': extra}, tags);

  Future<int> _create(
    int deckId,
    NoteType type,
    Map<String, String> fields,
    Iterable<String> tags,
  ) => db.transaction(() async {
    final indexes = _indexes(type, fields);
    final now = _now;
    final id = await db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            deckId: deckId,
            noteType: type.index,
            fieldsJson: jsonEncode(fields),
            createdAtUtc: now,
            modifiedAtUtc: now,
          ),
        );
    for (final index in indexes) {
      await db
          .into(db.cards)
          .insert(
            CardsCompanion.insert(
              noteId: id,
              clozeIndex: Value(index),
              dueAtUtc: now,
            ),
          );
    }
    await _writeTags(id, tags);
    await media.replaceReferences(const {}, fields);
    return id;
  });

  Future<Note> getNote(int id) async {
    final row = await _requireNote(id);
    final links = db.select(db.noteTags).join([
      innerJoin(db.tags, db.tags.id.equalsExp(db.noteTags.tagId)),
    ])..where(db.noteTags.noteId.equals(id));
    final tags =
        (await links.get()).map((r) => r.readTable(db.tags).name).toList()
          ..sort();
    return Note(
      id: row.id,
      deckId: row.deckId,
      type: NoteType.values[row.noteType],
      fields: Map<String, String>.from(jsonDecode(row.fieldsJson) as Map),
      tags: tags,
      createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.createdAtUtc,
        isUtc: true,
      ),
      modifiedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.modifiedAtUtc,
        isUtc: true,
      ),
    );
  }

  Future<void> updateNote(Note note, {bool allowCardRemoval = false}) =>
      db.transaction(() async {
        final old = await _requireNote(note.id);
        if (old.noteType != note.type.index) {
          throw ArgumentError('暂不支持直接更改卡片类型');
        }
        final indexes = _indexes(note.type, note.fields).toSet();
        final cards = await (db.select(
          db.cards,
        )..where((c) => c.noteId.equals(note.id))).get();
        final removed = cards
            .where((c) => !indexes.contains(c.clozeIndex))
            .toList();
        if (removed.isNotEmpty && !allowCardRemoval) {
          throw ClozeRemovalConfirmation(removed.map((c) => c.clozeIndex));
        }
        await (db.update(db.notes)..where((n) => n.id.equals(note.id))).write(
          NotesCompanion(
            deckId: Value(note.deckId),
            fieldsJson: Value(jsonEncode(note.fields)),
            modifiedAtUtc: Value(_now),
          ),
        );
        if (removed.isNotEmpty) {
          await (db.delete(
            db.cards,
          )..where((c) => c.id.isIn(removed.map((c) => c.id)))).go();
        }
        final existing = cards.map((c) => c.clozeIndex).toSet();
        for (final index in indexes.difference(existing)) {
          await db
              .into(db.cards)
              .insert(
                CardsCompanion.insert(
                  noteId: note.id,
                  clozeIndex: Value(index),
                  dueAtUtc: _now,
                ),
              );
        }
        await _writeTags(note.id, note.tags);
        await media.replaceReferences(
          media.fieldsFromJson(old.fieldsJson),
          note.fields,
        );
      });

  Future<void> deleteNote(int id) => db.transaction(() async {
    final old = await _requireNote(id);
    await media.replaceReferences(
      media.fieldsFromJson(old.fieldsJson),
      const {},
    );
    await (db.delete(db.notes)..where((n) => n.id.equals(id))).go();
  });

  List<int> _indexes(NoteType type, Map<String, String> fields) {
    if (type == NoteType.basic) {
      if ((fields['front'] ?? '').trim().isEmpty) {
        throw ArgumentError('请填写卡片正面');
      }
      return [0];
    }
    final indexes = _cloze.indexes(fields['text'] ?? '');
    if (indexes.isEmpty) throw ArgumentError('请添加至少一个 {{c1::内容}} 填空');
    return indexes;
  }

  Future<StoredNote> _requireNote(int id) async {
    final row = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(id))).getSingleOrNull();
    if (row == null) throw StateError('卡片不存在');
    return row;
  }

  Future<void> _writeTags(int noteId, Iterable<String> names) async {
    await (db.delete(db.noteTags)..where((n) => n.noteId.equals(noteId))).go();
    for (final name
        in names.map((s) => s.trim()).where((s) => s.isNotEmpty).toSet()) {
      await db
          .into(db.tags)
          .insert(
            TagsCompanion.insert(name: name),
            mode: InsertMode.insertOrIgnore,
          );
      final tag = await (db.select(
        db.tags,
      )..where((t) => t.name.equals(name))).getSingle();
      await db
          .into(db.noteTags)
          .insert(NoteTagsCompanion.insert(noteId: noteId, tagId: tag.id));
    }
  }

  int get _now => DateTime.now().toUtc().millisecondsSinceEpoch;
}
