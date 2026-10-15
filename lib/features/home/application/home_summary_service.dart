import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../settings/data/study_settings_repository.dart';
import '../../study/data/study_repository.dart';
import '../domain/home_summary.dart';

class HomeSummaryService {
  HomeSummaryService(this.db, {StudyRepository? study})
    : study = study ?? StudyRepository(db);

  final AppDatabase db;
  final StudyRepository study;
  DateTime get nowUtc => study.nowUtc;

  Stream<HomeSummary> watch() => db
      .customSelect(
        'SELECT 1',
        readsFrom: {
          db.decks,
          db.notes,
          db.cards,
          db.reviewLogs,
          db.appSettings,
        },
      )
      .watch()
      .asyncMap((_) => load());

  Future<HomeSummary> load() => db.transaction(() async {
    final settings = await StudySettingsRepository(db).load();
    final availability = await study.withSettings(settings).loadAvailability();
    final daily = await db
        .customSelect(
          '''
      SELECT COUNT(*) AS ratings, COUNT(DISTINCT card_id) AS cards
      FROM review_logs WHERE reviewed_at_utc >= ? AND reviewed_at_utc < ?
    ''',
          variables: [
            Variable(availability.dayStartUtc.millisecondsSinceEpoch),
            Variable(availability.dayEndUtc.millisecondsSinceEpoch),
          ],
          readsFrom: {db.reviewLogs},
        )
        .getSingle();
    final days = await db
        .customSelect(
          '''
      SELECT date(reviewed_at_utc / 1000.0, 'unixepoch', ? || ' minutes') AS day
      FROM review_logs WHERE reviewed_at_utc < ? GROUP BY day ORDER BY day DESC
    ''',
          variables: [
            Variable(availability.offsetMinutes),
            Variable(availability.dayEndUtc.millisecondsSinceEpoch),
          ],
          readsFrom: {db.reviewLogs},
        )
        .get();
    // Walk only the consecutive prefix of already grouped dates.
    var cursor = daily.read<int>('ratings') > 0
        ? availability.today
        : availability.today.subtract(const Duration(days: 1));
    var streak = 0;
    for (final row in days) {
      final date = DateTime.parse('${row.read<String>('day')}T00:00:00Z');
      if (date != cursor) break;
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    final deckCount = await db
        .customSelect(
          'SELECT COUNT(*) AS total FROM decks',
          readsFrom: {db.decks},
        )
        .getSingle();
    final decks = await db
        .customSelect(
          '''
      WITH RECURSIVE roots AS (
        SELECT id, name FROM decks WHERE parent_id IS NULL ORDER BY name, id LIMIT 5
      ), subtree(id, root_id) AS (
        SELECT id, id FROM roots
        UNION ALL
        SELECT d.id, s.root_id FROM decks d JOIN subtree s ON d.parent_id = s.id
      )
      SELECT r.id, r.name, COUNT(c.id) AS total FROM roots r
      JOIN subtree s ON s.root_id = r.id
      LEFT JOIN notes n ON n.deck_id = s.id LEFT JOIN cards c ON c.note_id = n.id
      GROUP BY r.id, r.name ORDER BY r.name, r.id
    ''',
          readsFrom: {db.decks, db.notes, db.cards},
        )
        .get();
    return HomeSummary(
      availability: availability,
      studiedCards: daily.read<int>('cards'),
      ratingCount: daily.read<int>('ratings'),
      streak: streak,
      deckCount: deckCount.read<int>('total'),
      decks: List.unmodifiable(
        decks.map(
          (row) => HomeDeckSummary(
            id: row.read<int>('id'),
            name: row.read<String>('name'),
            cardCount: row.read<int>('total'),
          ),
        ),
      ),
    );
  });
}
