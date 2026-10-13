import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/database/app_database.dart';
import '../features/decks/data/deck_repository.dart';
import '../features/decks/data/note_repository.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
final deckRepositoryProvider = Provider(
  (ref) => DeckRepository(ref.watch(databaseProvider)),
);
final noteRepositoryProvider = Provider(
  (ref) => NoteRepository(ref.watch(databaseProvider)),
);
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
