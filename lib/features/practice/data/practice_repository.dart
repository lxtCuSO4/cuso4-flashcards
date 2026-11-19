import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../decks/domain/choice_question.dart';
import '../../decks/domain/note.dart';
import '../domain/practice_session.dart';

export '../domain/practice_session.dart';

/// Practice results only update mistakes, never the formal learning schedule.
class PracticeRepository {
  PracticeRepository(this.db);
  final AppDatabase db;

  Future<bool> isEligible(PracticeScope scope, int cardId) async {
    final rows = await db
        .customSelect(
          '''
      WITH RECURSIVE scope(id) AS (
        SELECT id FROM decks WHERE id = ?
        UNION SELECT d.id FROM decks d JOIN scope s ON d.parent_id = s.id WHERE ? = 1
      )
      SELECT c.id FROM cards c JOIN notes n ON n.id = c.note_id
      WHERE c.id = ? AND (? IS NULL OR n.deck_id IN (SELECT id FROM scope))
        AND (? = 0 OR EXISTS (SELECT 1 FROM favorites f WHERE f.card_id = c.id))
        AND (? = 0 OR n.note_type IN (2, 3))
        AND (? = 0 OR EXISTS (SELECT 1 FROM wrong_questions w WHERE w.card_id = c.id))
    ''',
          variables: [
            Variable<int>(scope.deckId),
            Variable(scope.includeChildren ? 1 : 0),
            Variable(cardId),
            Variable<int>(scope.deckId),
            Variable(scope.favoritesOnly ? 1 : 0),
            Variable(scope.choicesOnly || scope.wrongOnly ? 1 : 0),
            Variable(scope.wrongOnly ? 1 : 0),
          ],
          readsFrom: {
            db.cards,
            db.notes,
            db.decks,
            db.favorites,
            db.wrongQuestions,
          },
        )
        .get();
    return rows.isNotEmpty;
  }

  Future<PracticeRound> sample({
    int? deckId,
    required bool includeChildren,
    bool favoritesOnly = false,
    bool choicesOnly = false,
    bool wrongOnly = false,
    PracticeOrder order = PracticeOrder.random,
  }) async {
    if (deckId == null && !favoritesOnly && !wrongOnly) {
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
          AND (? = 0 OR n.note_type IN (2, 3))
          AND (? = 0 OR EXISTS (SELECT 1 FROM wrong_questions w WHERE w.card_id = c.id))
        ORDER BY ${order == PracticeOrder.random ? 'RANDOM()' : 'c.id'}''',
            variables: [
              Variable<int>(deckId),
              Variable(includeChildren ? 1 : 0),
              Variable<int>(deckId),
              Variable(favoritesOnly ? 1 : 0),
              Variable(choicesOnly || wrongOnly ? 1 : 0),
              Variable(wrongOnly ? 1 : 0),
            ],
            readsFrom: {
              db.decks,
              db.notes,
              db.cards,
              db.favorites,
              db.wrongQuestions,
            },
          )
          .get();
      return PracticeRound(
        deckName: deck?.name ?? '全部牌组',
        cardIds: rows.map((r) => r.read<int>('id')),
      );
    });
  }

  Future<bool> submitChoice(
    int cardId,
    Set<int> selected, {
    required ChoiceQuestion expectedQuestion,
  }) => db.transaction(() async {
    final row = await db
        .customSelect(
          'SELECT n.note_type, n.fields_json FROM cards c JOIN notes n ON n.id = c.note_id WHERE c.id = ?',
          variables: [Variable(cardId)],
          readsFrom: {db.cards, db.notes},
        )
        .getSingleOrNull();
    if (row == null) throw StateError('题目已删除，请重新加载。');
    final type = NoteType.values[row.read<int>('note_type')];
    if (!type.isChoice) throw StateError('这张卡片不是选择题。');
    final question = ChoiceQuestion.fromFields(
      type,
      Map<String, String>.from(
        jsonDecode(row.read<String>('fields_json')) as Map,
      ),
    );
    if (type != expectedQuestion.type ||
        jsonEncode(question.toFields()) !=
            jsonEncode(expectedQuestion.toFields())) {
      throw StateError('题目已修改，请重新加载后作答。');
    }
    if (selected.isEmpty ||
        selected.any((i) => i < 0 || i >= question.options.length)) {
      throw ArgumentError('请选择有效的答案。');
    }
    final correct = question.isCorrect(selected);
    if (correct) {
      await (db.delete(
        db.wrongQuestions,
      )..where((w) => w.cardId.equals(cardId))).go();
    } else {
      await db.customInsert(
        '''INSERT INTO wrong_questions (card_id, wrong_count, last_wrong_at_utc) VALUES (?, 1, ?)
        ON CONFLICT(card_id) DO UPDATE SET wrong_count = wrong_count + 1, last_wrong_at_utc = excluded.last_wrong_at_utc''',
        variables: [
          Variable(cardId),
          Variable(DateTime.now().toUtc().millisecondsSinceEpoch),
        ],
        updates: {db.wrongQuestions},
      );
    }
    return correct;
  });
}
