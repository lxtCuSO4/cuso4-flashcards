import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../decks/data/note_repository.dart';
import '../../decks/domain/flashcard.dart';
import '../../settings/domain/study_settings.dart';
import '../domain/scheduler.dart';
import '../domain/study_card.dart';
import '../domain/study_availability.dart';
import 'fsrs_scheduler.dart';

class StudyRepository {
  StudyRepository(
    this.db, {
    Scheduler? scheduler,
    DateTime Function()? clock,
    Duration Function()? timezoneOffset,
    this.dailyNewLimit = 20,
    this.dailyReviewLimit = 200,
  }) : scheduler = scheduler ?? FsrsScheduler(),
       _clock = clock ?? DateTime.now,
       _timezoneOffset =
           timezoneOffset ?? (() => DateTime.now().timeZoneOffset) {
    if (dailyNewLimit < 0 || dailyReviewLimit < 0) {
      throw ArgumentError('每日额度不能为负数');
    }
  }
  final AppDatabase db;
  final Scheduler scheduler;
  final DateTime Function() _clock;
  final Duration Function() _timezoneOffset;
  final int dailyNewLimit;
  final int dailyReviewLimit;

  /// Keep a session's preview, queue and rating on one immutable configuration.
  StudyRepository withSettings(StudySettings settings) => StudyRepository(
    db,
    scheduler: FsrsScheduler(desiredRetention: settings.desiredRetention),
    clock: _clock,
    timezoneOffset: _timezoneOffset,
    dailyNewLimit: settings.dailyNewLimit,
    dailyReviewLimit: settings.dailyReviewLimit,
  );

  DateTime get nowUtc => DateTime.fromMillisecondsSinceEpoch(
    _clock().millisecondsSinceEpoch,
    isUtc: true,
  );

  // Share the exact candidate set and quota predicate between the bounded
  // learning queue and the unbounded, read-only homepage count.
  static const _candidateCtes = '''
      WITH RECURSIVE scope(id) AS (
        SELECT id FROM decks WHERE (? IS NULL OR id = ?)
        UNION ALL
        SELECT d.id FROM decks d JOIN scope s ON d.parent_id = s.id WHERE ? IS NOT NULL
      ), daily AS (
        SELECT COALESCE(json_extract(r.before_state_json, '\$.deckId'), n.deck_id) AS deck_id,
          COUNT(DISTINCT CASE WHEN json_extract(r.before_state_json, '\$.state') = 0 THEN r.card_id END) AS new_used,
          COUNT(DISTINCT CASE WHEN json_extract(r.before_state_json, '\$.state') = 2 THEN r.card_id END) AS review_used
        FROM review_logs r JOIN cards c ON c.id = r.card_id JOIN notes n ON n.id = c.note_id
        WHERE r.reviewed_at_utc >= ? AND r.reviewed_at_utc < ? GROUP BY 1
      ), eligible AS (
        SELECT c.*, n.deck_id, COALESCE(d.new_used, 0) AS new_used,
          COALESCE(d.review_used, 0) AS review_used,
          CASE WHEN c.state = 2 THEN 0 WHEN c.state IN (1, 3) THEN 1 ELSE 2 END AS priority
        FROM cards c JOIN notes n ON n.id = c.note_id LEFT JOIN daily d ON d.deck_id = n.deck_id
        WHERE n.deck_id IN (SELECT id FROM scope) AND c.state BETWEEN 0 AND 3
      ), ranked AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY deck_id, state ORDER BY due_at_utc, id) AS deck_position
        FROM eligible WHERE due_at_utc <= ?
      )
    ''';
  static const _quotaPredicate = '''state IN (1, 3)
        OR (state = 0 AND deck_position <= MAX(0, ? - new_used))
        OR (state = 2 AND deck_position <= MAX(0, ? - review_used))''';

  Future<StudyAvailability> loadAvailability() => db.transaction(() async {
    final now = nowUtc;
    final day = await _studyDay(now, pin: false);
    final row = await db
        .customSelect(
          '''$_candidateCtes
      SELECT COUNT(CASE WHEN state = 0 THEN 1 END) AS new_count,
        COUNT(CASE WHEN state = 2 THEN 1 END) AS review_count,
        COUNT(CASE WHEN state IN (1, 3) THEN 1 END) AS learning_count,
        (SELECT COUNT(*) FROM ranked WHERE state = 0) - COUNT(CASE WHEN state = 0 THEN 1 END) AS blocked_new,
        (SELECT COUNT(*) FROM ranked WHERE state = 2) - COUNT(CASE WHEN state = 2 THEN 1 END) AS blocked_review,
        (SELECT COUNT(*) FROM cards) AS total,
        (SELECT MIN(due_at_utc) FROM eligible WHERE due_at_utc > ? AND (
          state IN (1, 3) OR (state = 0 AND new_used < ?) OR (state = 2 AND review_used < ?)
        )) AS next_due
      FROM ranked WHERE $_quotaPredicate
    ''',
          variables: [
            const Variable<int>(null),
            const Variable<int>(null),
            const Variable<int>(null),
            Variable(day.start.millisecondsSinceEpoch),
            Variable(day.end.millisecondsSinceEpoch),
            Variable(now.millisecondsSinceEpoch),
            Variable(now.millisecondsSinceEpoch),
            Variable(dailyNewLimit),
            Variable(dailyReviewLimit),
            Variable(dailyNewLimit),
            Variable(dailyReviewLimit),
          ],
          readsFrom: {db.decks, db.notes, db.cards, db.reviewLogs},
        )
        .getSingle();
    final nextDue = row.readNullable<int>('next_due');
    return StudyAvailability(
      today: day.start.add(Duration(minutes: day.offsetMinutes)),
      dayStartUtc: day.start,
      dayEndUtc: day.end,
      offsetMinutes: day.offsetMinutes,
      newCards: row.read<int>('new_count'),
      reviews: row.read<int>('review_count'),
      learning: row.read<int>('learning_count'),
      blockedNewCards: row.read<int>('blocked_new'),
      blockedReviews: row.read<int>('blocked_review'),
      totalCards: row.read<int>('total'),
      nextDueAtUtc: nextDue == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(nextDue, isUtc: true),
    );
  });

  /// The same daily limits apply independently to each note's owning deck.
  /// Window ranks bound results even when many decks contain overdue cards.
  Future<List<Flashcard>> loadQueue({int? deckId, int limit = 50}) async {
    if (limit < 1 || limit > 500) throw ArgumentError('学习批次大小须为 1–500');
    if (deckId != null) {
      final deck = await (db.select(
        db.decks,
      )..where((d) => d.id.equals(deckId))).getSingleOrNull();
      if (deck == null) throw StateError('牌组不存在');
    }
    final now = nowUtc;
    final day = await _studyDay(now);
    final rows = await db
        .customSelect(
          '''$_candidateCtes
      SELECT ranked.*, CASE WHEN f.card_id IS NULL THEN 0 ELSE 1 END AS is_favorite
      FROM ranked LEFT JOIN favorites f ON f.card_id = ranked.id
      WHERE $_quotaPredicate
      ORDER BY priority, due_at_utc, id LIMIT ?
    ''',
          variables: [
            Variable<int>(deckId),
            Variable<int>(deckId),
            Variable<int>(deckId),
            Variable(day.start.millisecondsSinceEpoch),
            Variable(day.end.millisecondsSinceEpoch),
            Variable(now.millisecondsSinceEpoch),
            Variable(dailyNewLimit),
            Variable(dailyReviewLimit),
            Variable(limit),
          ],
          readsFrom: {
            db.decks,
            db.notes,
            db.cards,
            db.favorites,
            db.reviewLogs,
          },
        )
        .get();
    return rows.map(_fromRow).toList(growable: false);
  }

  Future<Flashcard> getCard(int id) async {
    final rows = await db
        .customSelect(
          '''SELECT c.*,
      CASE WHEN f.card_id IS NULL THEN 0 ELSE 1 END AS is_favorite
      FROM cards c LEFT JOIN favorites f ON f.card_id = c.id WHERE c.id = ?''',
          variables: [Variable(id)],
          readsFrom: {db.cards, db.favorites},
        )
        .get();
    if (rows.isEmpty) throw StateError('卡片不存在');
    return _fromRow(rows.single);
  }

  Future<StudyCard> getStudyCard(int id) => db.transaction(() async {
    final card = await getCard(id);
    final note = await NoteRepository(db).getNote(card.noteId);
    final deck = await (db.select(
      db.decks,
    )..where((d) => d.id.equals(note.deckId))).getSingle();
    return StudyCard(card: card, note: note, deckName: deck.name);
  });

  Future<ReviewReceipt> rateCard(
    Flashcard expected,
    ReviewRating rating, {
    Duration elapsed = Duration.zero,
  }) => db.transaction(() async {
    if (elapsed.isNegative) throw ArgumentError('学习耗时不能为负数');
    final current = await getCard(expected.id);
    if (!_sameSchedule(current, expected)) throw StateError('卡片进度已变化，请重新载入后评分');
    final now = nowUtc;
    if (current.dueAtUtc.isAfter(now)) throw StateError('这张卡片尚未到期');
    final note = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(current.noteId))).getSingle();
    final day = await _studyDay(now);
    final used = await _dailyUsage(note.deckId, day);
    if (current.state == CardState.newCard && used.newCards >= dailyNewLimit) {
      throw StateError('这个牌组今日的新卡额度已用完');
    }
    if (current.state == CardState.review && used.reviews >= dailyReviewLimit) {
      throw StateError('这个牌组今日的复习额度已用完');
    }
    final after = scheduler.applyReview(current, rating, reviewedAtUtc: now);
    await _writeCard(after);
    final id = await db
        .into(db.reviewLogs)
        .insert(
          ReviewLogsCompanion.insert(
            cardId: current.id,
            reviewedAtUtc: now.millisecondsSinceEpoch,
            rating: rating.value,
            elapsedMilliseconds: elapsed.inMilliseconds,
            beforeStateJson: jsonEncode({
              ...current.toJson(),
              'deckId': note.deckId,
            }),
            afterStateJson: jsonEncode({
              ...after.toJson(),
              'deckId': note.deckId,
            }),
          ),
        );
    return ReviewReceipt(logId: id, before: current, after: after);
  });

  /// Only the latest review can be undone, and only while its exact after-state
  /// is still current. Concurrent sessions therefore cannot erase newer work.
  Future<Flashcard> undoReview(int logId) => db.transaction(() async {
    final latest =
        await (db.select(db.reviewLogs)
              ..orderBy([(l) => OrderingTerm.desc(l.id)])
              ..limit(1))
            .getSingleOrNull();
    if (latest == null || latest.id != logId) throw StateError('只能撤销最近一次评分');
    final before = Flashcard.fromJson(
      jsonDecode(latest.beforeStateJson) as Map<String, dynamic>,
    );
    final after = Flashcard.fromJson(
      jsonDecode(latest.afterStateJson) as Map<String, dynamic>,
    );
    final current = await getCard(latest.cardId);
    if (!_sameSchedule(current, after)) throw StateError('卡片进度已变化，无法撤销');
    await _writeCard(before);
    await (db.delete(db.reviewLogs)..where((l) => l.id.equals(logId))).go();
    return getCard(before.id);
  });

  Future<void> setFavorite(int cardId, bool value) => db.transaction(() async {
    await getCard(cardId);
    if (value) {
      await db
          .into(db.favorites)
          .insert(
            FavoritesCompanion.insert(
              cardId: Value(cardId),
              createdAtUtc: nowUtc.millisecondsSinceEpoch,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } else {
      await (db.delete(
        db.favorites,
      )..where((f) => f.cardId.equals(cardId))).go();
    }
  });

  Future<void> _writeCard(Flashcard card) async {
    await (db.update(db.cards)..where((c) => c.id.equals(card.id))).write(
      CardsCompanion(
        dueAtUtc: Value(card.dueAtUtc.millisecondsSinceEpoch),
        state: Value(card.state.index),
        stability: Value(card.stability),
        difficulty: Value(card.difficulty),
        learningStep: Value(card.learningStep),
        repetitions: Value(card.repetitions),
        lapses: Value(card.lapses),
        lastReviewAtUtc: Value(card.lastReviewAtUtc?.millisecondsSinceEpoch),
      ),
    );
  }

  bool _sameSchedule(Flashcard first, Flashcard second) =>
      jsonEncode(first.toJson()) == jsonEncode(second.toJson());

  Flashcard _fromRow(QueryRow row) => Flashcard(
    id: row.read<int>('id'),
    noteId: row.read<int>('note_id'),
    clozeIndex: row.read<int>('cloze_index') == 0
        ? null
        : row.read<int>('cloze_index'),
    dueAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row.read<int>('due_at_utc'),
      isUtc: true,
    ),
    state: CardState.values[row.read<int>('state')],
    stability: row.readNullable<double>('stability'),
    difficulty: row.readNullable<double>('difficulty'),
    learningStep: row.read<int>('learning_step'),
    repetitions: row.read<int>('repetitions'),
    lapses: row.read<int>('lapses'),
    lastReviewAtUtc: row.readNullable<int>('last_review_at_utc') == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            row.read<int>('last_review_at_utc'),
            isUtc: true,
          ),
    isFavorite: row.read<int>('is_favorite') != 0,
  );

  Future<({int newCards, int reviews})> _dailyUsage(
    int deckId,
    ({DateTime start, DateTime end, int offsetMinutes}) day,
  ) async {
    final row = await db
        .customSelect(
          '''SELECT
      COUNT(DISTINCT CASE WHEN json_extract(r.before_state_json, '\$.state') = 0 THEN r.card_id END) AS new_used,
      COUNT(DISTINCT CASE WHEN json_extract(r.before_state_json, '\$.state') = 2 THEN r.card_id END) AS review_used
      FROM review_logs r JOIN cards c ON c.id = r.card_id JOIN notes n ON n.id = c.note_id
      WHERE r.reviewed_at_utc >= ? AND r.reviewed_at_utc < ?
        AND COALESCE(json_extract(r.before_state_json, '\$.deckId'), n.deck_id) = ?''',
          variables: [
            Variable(day.start.millisecondsSinceEpoch),
            Variable(day.end.millisecondsSinceEpoch),
            Variable(deckId),
          ],
          readsFrom: {db.reviewLogs, db.cards, db.notes},
        )
        .getSingle();
    return (
      newCards: row.read<int>('new_used'),
      reviews: row.read<int>('review_used'),
    );
  }

  /// Pin the learning-day offset on first use, so changing device timezone
  /// cannot grant a second daily allowance.
  Future<({DateTime start, DateTime end, int offsetMinutes})> _studyDay(
    DateTime now, {
    bool pin = true,
  }) async {
    const key = 'studyDayOffsetMinutes';
    var setting = await (db.select(
      db.appSettings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    if (setting == null && pin) {
      final minutes = _timezoneOffset().inMinutes;
      if (minutes < -840 || minutes > 840) throw ArgumentError('学习日时区偏移无效');
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: key,
              valueJson: jsonEncode(minutes),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      setting = await (db.select(
        db.appSettings,
      )..where((s) => s.key.equals(key))).getSingle();
    }
    Object? minutes;
    try {
      minutes = setting == null
          ? _timezoneOffset().inMinutes
          : jsonDecode(setting.valueJson);
    } on FormatException {
      throw StateError('学习日设置无效');
    }
    if (minutes is! int || minutes < -840 || minutes > 840) {
      throw StateError('学习日设置无效');
    }
    final offset = Duration(minutes: minutes);
    final local = now.add(offset);
    final start = DateTime.utc(
      local.year,
      local.month,
      local.day,
    ).subtract(offset);
    return (
      start: start,
      end: start.add(const Duration(days: 1)),
      offsetMinutes: minutes,
    );
  }
}
