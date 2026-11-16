import 'package:drift/drift.dart';

import 'database_connection.dart';
import 'tables/app_settings.dart';
import 'tables/cards.dart';
import 'tables/decks.dart';
import 'tables/import_jobs.dart';
import 'tables/media.dart';
import 'tables/notes.dart';
import 'tables/review_logs.dart';
import 'tables/tags.dart';
import 'tables/wrong_questions.dart';

part 'app_database.g.dart';

/// Persisted time fields are UTC epoch milliseconds, including review snapshots.
@DriftDatabase(
  tables: [
    Decks,
    Notes,
    Cards,
    Tags,
    NoteTags,
    ReviewLogs,
    Media,
    Favorites,
    WrongQuestions,
    AppSettings,
    ImportJobs,
    ImportJobErrors,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? connection])
    : super(connection ?? openLocalDatabase());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (_) async => customStatement('PRAGMA foreign_keys = ON'),
    onUpgrade: (migrator, from, to) async {
      if (from == 1 && to == 2) {
        await migrator.createTable(wrongQuestions);
      } else {
        throw StateError('数据库版本 $from 无法升级至 $to，请保留数据并更新应用。');
      }
    },
  );
}
