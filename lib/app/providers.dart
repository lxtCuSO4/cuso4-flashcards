import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show mapEquals;

import '../core/database/app_database.dart';
import '../core/media/media_repository.dart';
import '../features/decks/data/deck_repository.dart';
import '../features/decks/data/note_repository.dart';
import '../features/decks/data/choice_conversion_repository.dart';
import '../features/import/application/import_controller.dart';
import '../features/import/data/apkg_import_service.dart';
import '../features/import/data/import_recovery_repository.dart';
import '../features/study/data/study_repository.dart';
import '../features/settings/data/study_settings_repository.dart';
import '../features/settings/data/font_settings_repository.dart';
import '../features/records/data/statistics_repository.dart';
import '../features/home/application/home_summary_service.dart';
import '../features/practice/data/practice_repository.dart';

final practiceRepositoryProvider = Provider(
  (ref) => PracticeRepository(ref.watch(databaseProvider)),
);

final homeSummaryServiceProvider = Provider(
  (ref) => HomeSummaryService(
    ref.watch(databaseProvider),
    study: ref.watch(studyRepositoryProvider),
  ),
);

final homeSummaryProvider = StreamProvider.autoDispose(
  (ref) => ref.watch(homeSummaryServiceProvider).watch(),
);

final statisticsRepositoryProvider = Provider(
  (ref) => StatisticsRepository(ref.watch(databaseProvider)),
);

final studySettingsRepositoryProvider = Provider(
  (ref) => StudySettingsRepository(ref.watch(databaseProvider)),
);

final fontSettingsRepositoryProvider = Provider(
  (ref) => FontSettingsRepository(ref.watch(databaseProvider)),
);

final studyRepositoryProvider = Provider(
  (ref) => StudyRepository(ref.watch(databaseProvider)),
);

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
final deckRepositoryProvider = Provider(
  (ref) => DeckRepository(
    ref.watch(databaseProvider),
    mediaRepository: ref.watch(mediaRepositoryProvider),
  ),
);
final noteRepositoryProvider = Provider(
  (ref) => NoteRepository(
    ref.watch(databaseProvider),
    mediaRepository: ref.watch(mediaRepositoryProvider),
  ),
);
final mediaRepositoryProvider = Provider(
  (ref) => MediaRepository(ref.watch(databaseProvider)),
);
final choiceConversionRepositoryProvider = Provider(
  (ref) => ChoiceConversionRepository(
    ref.watch(databaseProvider),
    mediaRepository: ref.watch(mediaRepositoryProvider),
  ),
);
final importServiceProvider = Provider(
  (ref) => ApkgImportService(ref.watch(databaseProvider)),
);
final importRecoveryRepositoryProvider = Provider(
  (ref) => ImportRecoveryRepository(ref.watch(databaseProvider)),
);
final importRecoveryNoticeProvider = StreamProvider(
  (ref) => ref.watch(importRecoveryRepositoryProvider).watch(),
);
final importControllerProvider = Provider((ref) {
  final service = ref.watch(importServiceProvider);
  final controller = ImportController(
    (file, {required merge, required isCancelled, required onProgress}) =>
        service.importFile(
          file,
          merge: merge,
          isCancelled: isCancelled,
          onProgress: onProgress,
        ),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

Future<void> cleanUpUnusedMedia(MediaRepository repository) async {
  try {
    await repository.collectUnused();
  } catch (_) {
    // Best effort. A cleanup error must not turn a committed save into failure.
  }
}

final decksProvider = StreamProvider(
  (ref) => ref.watch(deckRepositoryProvider).watchDeckTree(),
);
final settingsProvider = StreamProvider((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        "SELECT key, value_json FROM app_settings WHERE key < 'practice:' OR key >= 'practice;'",
        readsFrom: {db.appSettings},
      )
      .watch()
      .map(
        (rows) => {
          for (final row in rows)
            row.read<String>('key'): row.read<String>('value_json'),
        },
      )
      .distinct((before, after) => mapEquals(before, after));
});

final cardCountsProvider = StreamProvider((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        '''WITH RECURSIVE subtree(root_id, deck_id) AS (
      SELECT id, id FROM decks
      UNION
      SELECT s.root_id, d.id FROM decks d JOIN subtree s ON d.parent_id = s.deck_id
    ), direct_counts AS (
      SELECT n.deck_id, COUNT(c.id) AS total
      FROM notes n JOIN cards c ON c.note_id = n.id GROUP BY n.deck_id
    )
    SELECT s.root_id AS deck_id, COALESCE(SUM(c.total), 0) AS total,
      COUNT(*) - 1 AS chapters
    FROM subtree s LEFT JOIN direct_counts c ON c.deck_id = s.deck_id
    GROUP BY s.root_id''',
        readsFrom: {db.decks, db.notes, db.cards},
      )
      .watch()
      .map(
        (rows) => {
          for (final row in rows)
            row.read<int>('deck_id'): (
              cards: row.read<int>('total'),
              chapters: row.read<int>('chapters'),
            ),
        },
      );
});

Future<void> saveSetting(WidgetRef ref, String key, String value) => ref
    .read(databaseProvider)
    .into(ref.read(databaseProvider).appSettings)
    .insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, valueJson: value),
    );
