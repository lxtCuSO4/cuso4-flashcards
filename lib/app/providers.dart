import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../core/media/media_repository.dart';
import '../features/decks/data/deck_repository.dart';
import '../features/decks/data/note_repository.dart';
import '../features/import/application/import_controller.dart';
import '../features/import/data/apkg_import_service.dart';
import '../features/study/data/study_repository.dart';
import '../features/settings/data/study_settings_repository.dart';
import '../features/records/data/statistics_repository.dart';

final statisticsRepositoryProvider = Provider(
  (ref) => StatisticsRepository(ref.watch(databaseProvider)),
);

final studySettingsRepositoryProvider = Provider(
  (ref) => StudySettingsRepository(ref.watch(databaseProvider)),
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
final importServiceProvider = Provider(
  (ref) => ApkgImportService(ref.watch(databaseProvider)),
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
final settingsProvider = StreamProvider(
  (ref) => ref
      .watch(databaseProvider)
      .select(ref.watch(databaseProvider).appSettings)
      .watch()
      .map((rows) => {for (final row in rows) row.key: row.valueJson}),
);

final cardCountsProvider = StreamProvider((ref) {
  final db = ref.watch(databaseProvider);
  return db
      .customSelect(
        '''SELECT n.deck_id AS deck_id, COUNT(c.id) AS total
    FROM notes n JOIN cards c ON c.note_id = n.id GROUP BY n.deck_id''',
        readsFrom: {db.notes, db.cards},
      )
      .watch()
      .map(
        (rows) => {
          for (final row in rows)
            row.read<int>('deck_id'): row.read<int>('total'),
        },
      );
});

Future<void> saveSetting(WidgetRef ref, String key, String value) => ref
    .read(databaseProvider)
    .into(ref.read(databaseProvider).appSettings)
    .insertOnConflictUpdate(
      AppSettingsCompanion.insert(key: key, valueJson: value),
    );
