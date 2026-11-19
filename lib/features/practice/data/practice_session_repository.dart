import 'dart:convert';
import 'dart:math';

import 'package:uuid/uuid.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:html/parser.dart' as html;
import 'package:crypto/crypto.dart';

import '../../../core/database/app_database.dart';
import '../../decks/domain/choice_attempt.dart';
import '../../decks/domain/choice_question.dart';
import 'practice_repository.dart';

/// Small independent progress records use the existing backed-up SQLite settings.
/// Every read/modify/write and grading operation is serialized by a transaction.
class PracticeSessionRepository {
  PracticeSessionRepository(this.practice, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final PracticeRepository practice;
  final DateTime Function() _clock;
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
      if (queue['version'] == 1) {
        queue['version'] = 2;
        queue['legacyBefore'] = cursor['completed'] == true
            ? (queue['cardIds'] as List).length
            : cursor['index'];
        await _write('${scope.key}:queue', queue);
      }
      final session = PracticeSession.decode(scope, queue, cursor);
      // Import the last v1 answer without inventing a submission timestamp.
      if (cursor['version'] == 1 &&
          session.cardId != null &&
          session.signature.isNotEmpty) {
        await _write(_cardKey(session.id, session.cardId!), session.cursor);
        await _write('${scope.key}:cursor', session.cursor);
      }
      return session;
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
        String? previousId;
        if (!restart) {
          final saved = await _read(scope);
          if (saved != null) return saved;
        } else {
          // Restart must still work when the old cursor or queue is corrupt.
          try {
            previousId =
                (await _readJson('${scope.key}:queue'))?['id'] as String?;
          } catch (_) {
            previousId = null;
          }
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
        if (previousId != null) {
          await db.customUpdate(
            'DELETE FROM app_settings WHERE key >= ? AND key < ?',
            variables: [
              Variable('practice:card:$previousId:'),
              Variable('practice:card:$previousId;'),
            ],
            updates: {db.appSettings},
          );
        }
        await _write('${scope.key}:queue', {
          'version': 2,
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
    if (session.signature.isNotEmpty) {
      session = session.copyWith(signature: _fingerprint(session.signature));
    }
    if (session.cardId != null) {
      await _write(_cardKey(session.id, session.cardId!), session.cursor);
    }
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
    final fingerprint = _fingerprint(signature);
    if (_fingerprint(current.signature) == fingerprint) {
      return current.signature == fingerprint
          ? current
          : _save(current.copyWith(signature: fingerprint));
    }
    final order = List.generate(optionCount, (i) => i);
    if (shuffle) order.shuffle(Random());
    return _save(
      current.copyWith(
        resetCard: true,
        signature: fingerprint,
        isChoice: isChoice,
        order: order,
        correct: current.correct - (current.currentCorrect == 1 ? 1 : 0),
        incorrect: current.incorrect - (current.currentCorrect == 0 ? 1 : 0),
        skipped: current.skipped - (current.wasSkipped ? 1 : 0),
        unanswered:
            current.unanswered -
            (current.settled &&
                    current.isChoice &&
                    !current.attempted &&
                    !current.wasSkipped &&
                    !current.legacyReview
                ? 1
                : 0),
        generation: current.generation + (current.signature.isEmpty ? 0 : 1),
        legacyReview: current.legacyReview,
        answerVisible: current.legacyReview,
        settled: current.legacyReview,
        roundFinished: current.legacyReview ? current.roundFinished : false,
      ),
    );
  });

  Future<PracticeSession> saveAttempt(
    PracticeSession expected,
    ChoiceAttemptSnapshot attempt, {
    int? elapsedMs,
  }) => db.transaction(() async {
    final current = await _current(expected);
    if (current.answerVisible || current.attempted) return current;
    if (jsonEncode(current.optionOrder) != jsonEncode(attempt.order) ||
        attempt.selected.any((v) => !current.optionOrder.contains(v))) {
      throw StateError('选项已经变化，请重新加载题目。');
    }
    return _save(
      current.copyWith(
        selected: attempt.selected,
        wasSkipped: false,
        settled: false,
        skipped: current.skipped - (current.wasSkipped ? 1 : 0),
        roundFinished: current.wasSkipped ? false : current.roundFinished,
        elapsedMs: max(current.elapsedMs, elapsedMs ?? 0),
      ),
    );
  });

  Future<PracticeSession> reveal(
    PracticeSession expected, {
    bool explanation = false,
  }) => db.transaction(() async {
    final current = await _current(expected);
    return _save(
      current.copyWith(
        answerVisible: true,
        explanation: explanation,
        wasSkipped: false,
        skipped: current.skipped - (current.wasSkipped ? 1 : 0),
        settled: current.wasSkipped ? false : current.settled,
        roundFinished: current.wasSkipped ? false : current.roundFinished,
      ),
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
    int? elapsedMs,
    String? sourceDeckName,
  }) => db.transaction(() async {
    final current = await _current(expected);
    if (current.attempted) return current;
    if (current.legacyReview) throw StateError('旧版题目没有历史答案，请新开一轮后重新作答。');
    if (current.answerVisible) throw StateError('已查看答案的题目不能再次提交。');
    final correct = await practice.submitChoice(
      current.cardId!,
      selected,
      expectedQuestion: question,
    );
    final now = _clock().toUtc();
    final elapsed = max(current.elapsedMs, elapsedMs ?? 0);
    final day = now.toIso8601String().substring(0, 10);
    await _write(
      'practice:attempt:$day:${current.id}:${current.cardId}:${current.generation}',
      {
        'version': 1,
        'submittedAtUtc': now.millisecondsSinceEpoch,
        'sessionId': current.id,
        'cardId': current.cardId,
        'deckId': current.scope.deckId,
        'deckName': current.round.deckName,
        'correct': correct,
        'elapsedMs': elapsed,
        'source': current.scope.wrongOnly
            ? 'wrong'
            : current.scope.favoritesOnly
            ? 'favorites'
            : 'deck',
        'prompt': (html.parseFragment(question.prompt).text ?? '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .split('')
            .take(180)
            .join(),
        'sourceDeckName': sourceDeckName ?? current.round.deckName,
      },
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
        settled: true,
        elapsedMs: elapsed,
        wasSkipped: false,
        skipped: current.skipped - (current.wasSkipped ? 1 : 0),
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
    final saved = current.copyWith(
      settled: true,
      wasSkipped: current.wasSkipped || skip,
      skipped: current.skipped + (skip && !current.settled ? 1 : 0),
      unanswered:
          current.unanswered +
          (!skip && !current.settled && current.isChoice && !current.attempted
              ? 1
              : 0),
    );
    await _save(saved);
    var next = current.index + 1;
    var finished = false;
    if (next >= current.round.cardIds.length) {
      final records = await _cardRecords(current.id);
      next = -1;
      for (
        var i = current.round.legacyBefore;
        i < current.round.cardIds.length;
        i++
      ) {
        if (records[current.round.cardIds[i]]?['settled'] != true) {
          next = i;
          break;
        }
      }
      finished = next < 0;
      if (finished) next = current.round.cardIds.length;
    }
    if (finished) {
      return _save(
        saved.copyWith(
          index: next,
          completed: true,
          roundFinished: true,
          resetCard: true,
        ),
      );
    }
    return _moveTo(saved, next);
  });

  String _cardKey(String roundId, int cardId) =>
      'practice:card:$roundId:$cardId';

  String _fingerprint(String value) =>
      value.isEmpty || RegExp(r'^[a-f0-9]{64}$').hasMatch(value)
      ? value
      : sha256.convert(utf8.encode(value)).toString();

  Future<Map<int, Map<String, dynamic>>> _cardRecords(String roundId) async {
    final rows = await db
        .customSelect(
          'SELECT key, value_json FROM app_settings WHERE key GLOB ?',
          variables: [Variable('practice:card:$roundId:*')],
          readsFrom: {db.appSettings},
        )
        .get();
    return {
      for (final row in rows)
        int.parse(
          row.read<String>('key').split(':').last,
        ): Map<String, dynamic>.from(
          jsonDecode(row.read<String>('value_json')) as Map,
        ),
    };
  }

  Future<PracticeSession> _moveTo(PracticeSession current, int index) async {
    final cardId = current.round.cardIds[index];
    final record = await _readJson(_cardKey(current.id, cardId));
    final legacy = record == null && index < current.round.legacyBefore;
    final cursor = {
      ...current
          .copyWith(
            index: index,
            completed: false,
            resetCard: true,
            legacyReview: legacy,
            answerVisible: legacy,
            settled: legacy,
          )
          .cursor,
    };
    if (record != null) {
      for (final key in [
        'signature',
        'isChoice',
        'order',
        'selected',
        'attempted',
        'answerVisible',
        'explanation',
        'currentCorrect',
        'settled',
        'wasSkipped',
        'legacyReview',
        'elapsedMs',
        'generation',
      ]) {
        if (record.containsKey(key)) cursor[key] = record[key]!;
      }
    }
    final moved = PracticeSession.decode(current.scope, {
      'version': 2,
      'id': current.id,
      'deckName': current.round.deckName,
      'cardIds': current.round.cardIds,
      'legacyBefore': current.round.legacyBefore,
    }, cursor);
    return _save(moved);
  }

  Future<PracticeSession> jump(PracticeSession expected, int index) =>
      db.transaction(() async {
        var current = await _current(expected);
        if (index < 0 || index >= current.round.cardIds.length) {
          throw ArgumentError('题号无效');
        }
        if (!current.completed && current.answerVisible && !current.settled) {
          current = await _save(
            current.copyWith(
              settled: true,
              unanswered:
                  current.unanswered +
                  (current.isChoice && !current.attempted ? 1 : 0),
            ),
          );
        }
        return _moveTo(current, index);
      });

  Future<PracticeSession> showSummary(PracticeSession expected) =>
      db.transaction(() async {
        final current = await _current(expected);
        if (!current.roundFinished) throw StateError('本轮还有未完成题目。');
        return _save(
          current.copyWith(
            index: current.round.cardIds.length,
            completed: true,
            resetCard: true,
          ),
        );
      });

  Future<void> saveElapsed(PracticeSession expected, int elapsedMs) =>
      db.transaction(() async {
        final current = await _current(expected);
        if (!current.answerVisible && !current.completed) {
          await _save(
            current.copyWith(elapsedMs: max(current.elapsedMs, elapsedMs)),
          );
        }
      });

  Future<List<PracticeAnswer>> answers(PracticeSession session) =>
      db.transaction(() async {
        final records = await _cardRecords(session.id);
        final favorites = (await db.select(db.favorites).get())
            .map((f) => f.cardId)
            .toSet();
        return List.generate(session.round.cardIds.length, (index) {
          final id = session.round.cardIds[index];
          final record = records[id];
          PracticeAnswerStatus status;
          if (record == null && index < session.round.legacyBefore ||
              record?['legacyReview'] == true) {
            status = PracticeAnswerStatus.legacy;
          } else if (record?['attempted'] == true) {
            status = record?['currentCorrect'] == 1
                ? PracticeAnswerStatus.correct
                : PracticeAnswerStatus.wrong;
          } else if (record?['wasSkipped'] == true) {
            status = PracticeAnswerStatus.skipped;
          } else if (record?['answerVisible'] == true) {
            status = PracticeAnswerStatus.viewed;
          } else {
            status = PracticeAnswerStatus.pending;
          }
          return PracticeAnswer(
            id,
            index,
            status,
            favorite: favorites.contains(id),
          );
        });
      });
}
