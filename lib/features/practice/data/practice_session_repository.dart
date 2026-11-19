import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';

import '../../../core/database/app_database.dart';
import '../../decks/domain/choice_attempt.dart';
import '../../decks/domain/choice_question.dart';
import 'practice_repository.dart';

/// Small independent progress records use the existing backed-up SQLite settings.
/// Every read/modify/write and grading operation is serialized by a transaction.
class PracticeSessionRepository {
  PracticeSessionRepository(this.practice);
  final PracticeRepository practice;
  AppDatabase get db => practice.db;

  Future<Map<String, dynamic>?> _readJson(String key) async {
    final row = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    if (row == null) return null;
    return Map<String, dynamic>.from(jsonDecode(row.valueJson) as Map);
  }

  Future<void> _write(String key, Map<String, dynamic> value) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(key: key, valueJson: jsonEncode(value)),
        );
  }

  Future<PracticeSession?> _read(PracticeScope scope) async {
    try {
      final queue = await _readJson('${scope.key}:queue');
      final cursor = await _readJson('${scope.key}:cursor');
      if (queue == null && cursor == null) return null;
      if (queue == null || cursor == null) throw const FormatException();
      return PracticeSession.decode(scope, queue, cursor);
    } catch (_) {
      throw StateError('练习进度无法读取。可选择从头练习，现有卡片和错题不会被清除。');
    }
  }

  Future<PracticeSession?> peek(PracticeScope scope) =>
      db.transaction(() => _read(scope));

  Future<({bool includeChildren, PracticeOrder order})> preferences(
    PracticeScope defaults, {
    required bool entryChildren,
  }) async {
    final saved = await _readJson(
      'practice:pref:${defaults.entryKey}:$entryChildren',
    );
    return (
      includeChildren: saved?['includeChildren'] is bool
          ? saved!['includeChildren'] as bool
          : defaults.includeChildren,
      order:
          PracticeOrder.values
              .where((v) => v.name == saved?['order'])
              .firstOrNull ??
          defaults.order,
    );
  }

  Future<void> remember(PracticeScope scope, {required bool entryChildren}) =>
      _write('practice:pref:${scope.entryKey}:$entryChildren', {
        'includeChildren': scope.includeChildren,
        'order': scope.order.name,
      });

  Future<PracticeSession> open(PracticeScope scope, {bool restart = false}) =>
      db.transaction(() async {
        if (!restart) {
          final saved = await _read(scope);
          if (saved != null) return saved;
        }
        final round = await practice.sample(
          deckId: scope.deckId,
          includeChildren: scope.includeChildren,
          favoritesOnly: scope.favoritesOnly,
          choicesOnly: scope.choicesOnly,
          wrongOnly: scope.wrongOnly,
          order: scope.order,
        );
        final session = PracticeSession(
          scope: scope,
          id: const Uuid().v4(),
          round: round,
          completed: round.cardIds.isEmpty,
        );
        await _write('${scope.key}:queue', {
          'version': 1,
          'id': session.id,
          'deckName': round.deckName,
          'cardIds': round.cardIds,
        });
        return _save(session);
      });

  Future<PracticeSession> _current(PracticeSession expected) async {
    final current = await _read(expected.scope);
    if (current == null ||
        current.id != expected.id ||
        current.index != expected.index) {
      throw StateError('练习进度已变化，请重新进入继续练习。');
    }
    return current;
  }

  Future<PracticeSession> _save(PracticeSession session) async {
    await _write('${session.scope.key}:cursor', session.cursor);
    return session;
  }

  Future<PracticeSession> bindQuestion(
    PracticeSession expected, {
    required String signature,
    required bool isChoice,
    int optionCount = 0,
    bool shuffle = false,
  }) => db.transaction(() async {
    final current = await _current(expected);
    if (current.signature == signature) return current;
    final order = List.generate(optionCount, (i) => i);
    if (shuffle) order.shuffle(Random());
    return _save(
      current.copyWith(
        resetCard: true,
        signature: signature,
        isChoice: isChoice,
        order: order,
        correct: current.correct - (current.currentCorrect == 1 ? 1 : 0),
        incorrect: current.incorrect - (current.currentCorrect == 0 ? 1 : 0),
      ),
    );
  });

  Future<PracticeSession> saveAttempt(
    PracticeSession expected,
    ChoiceAttemptSnapshot attempt,
  ) => db.transaction(() async {
    final current = await _current(expected);
    if (current.answerVisible || current.attempted) return current;
    if (jsonEncode(current.optionOrder) != jsonEncode(attempt.order) ||
        attempt.selected.any((v) => !current.optionOrder.contains(v))) {
      throw StateError('选项已经变化，请重新加载题目。');
    }
    return _save(current.copyWith(selected: attempt.selected));
  });

  Future<PracticeSession> reveal(
    PracticeSession expected, {
    bool explanation = false,
  }) => db.transaction(() async {
    final current = await _current(expected);
    return _save(
      current.copyWith(answerVisible: true, explanation: explanation),
    );
  });

  Future<PracticeSession> explanation(PracticeSession expected, bool visible) =>
      db.transaction(() async {
        final current = await _current(expected);
        return _save(current.copyWith(explanation: visible));
      });

  Future<PracticeSession> submit(
    PracticeSession expected,
    Set<int> selected, {
    required ChoiceQuestion question,
  }) => db.transaction(() async {
    final current = await _current(expected);
    if (current.attempted) return current;
    if (current.answerVisible) throw StateError('已查看答案的题目不能再次提交。');
    final correct = await practice.submitChoice(
      current.cardId!,
      selected,
      expectedQuestion: question,
    );
    return _save(
      current.copyWith(
        selected: selected,
        attempted: true,
        answerVisible: true,
        explanation: true,
        currentCorrect: correct ? 1 : 0,
        correct: current.correct + (correct ? 1 : 0),
        incorrect: current.incorrect + (correct ? 0 : 1),
      ),
    );
  });

  Future<PracticeSession> advance(
    PracticeSession expected, {
    bool skip = false,
  }) => db.transaction(() async {
    final current = await _current(expected);
    if (current.completed) return current;
    if (!skip && !current.answerVisible) throw StateError('请先显示或提交答案。');
    final next = current.index + 1;
    return _save(
      current.copyWith(
        index: next,
        completed: next >= current.round.cardIds.length,
        resetCard: true,
        skipped: current.skipped + (skip ? 1 : 0),
        unanswered:
            current.unanswered +
            (!skip && current.isChoice && !current.attempted ? 1 : 0),
      ),
    );
  });
}
