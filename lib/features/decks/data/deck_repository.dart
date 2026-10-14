import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/media/media_repository.dart';

class DeckRepository {
  DeckRepository(this.db, {MediaRepository? mediaRepository})
    : media = mediaRepository ?? MediaRepository(db);
  final AppDatabase db;
  final MediaRepository media;

  Stream<List<StoredDeck>> watchDeckTree() =>
      (db.select(db.decks)..orderBy([(d) => OrderingTerm.asc(d.name)])).watch();

  Future<int> createDeck(String name, {int? parentId}) =>
      db.transaction(() async {
        if (parentId != null) await _require(parentId);
        final now = _now;
        return db
            .into(db.decks)
            .insert(
              DecksCompanion.insert(
                name: _name(name),
                parentId: Value(parentId),
                createdAtUtc: now,
                modifiedAtUtc: now,
              ),
            );
      });

  Future<void> renameDeck(int id, String name) => db.transaction(() async {
    await _require(id);
    await (db.update(db.decks)..where((d) => d.id.equals(id))).write(
      DecksCompanion(name: Value(_name(name)), modifiedAtUtc: Value(_now)),
    );
  });

  Future<void> moveDeck(int id, int? parentId) => db.transaction(() async {
    await _require(id);
    var ancestor = parentId;
    final visited = <int>{};
    while (ancestor != null) {
      if (ancestor == id || !visited.add(ancestor)) {
        throw ArgumentError('不能移入自身或子牌组');
      }
      ancestor = (await _require(ancestor)).parentId;
    }
    await (db.update(db.decks)..where((d) => d.id.equals(id))).write(
      DecksCompanion(parentId: Value(parentId), modifiedAtUtc: Value(_now)),
    );
  });

  Future<void> deleteDeck(int id) => db.transaction(() async {
    await _require(id);
    final tree = await db.select(db.decks).get();
    final descendants = <int>{id};
    var previousCount = 0;
    while (previousCount != descendants.length) {
      previousCount = descendants.length;
      descendants.addAll(
        tree.where((d) => descendants.contains(d.parentId)).map((d) => d.id),
      );
    }
    final notes = await (db.select(
      db.notes,
    )..where((n) => n.deckId.isIn(descendants))).get();
    for (final note in notes) {
      await media.replaceReferences(
        media.fieldsFromJson(note.fieldsJson),
        const {},
      );
    }
    await (db.delete(db.decks)..where((d) => d.id.equals(id))).go();
  });

  int get _now => DateTime.now().toUtc().millisecondsSinceEpoch;

  Future<StoredDeck> _require(int id) async {
    final row = await (db.select(
      db.decks,
    )..where((d) => d.id.equals(id))).getSingleOrNull();
    if (row == null) throw StateError('牌组不存在');
    return row;
  }

  String _name(String name) {
    final value = name.trim();
    if (value.isEmpty || value.length > 255) {
      throw ArgumentError('牌组名称须为 1–255 个字符');
    }
    return value;
  }
}
