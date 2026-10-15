import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/practice/data/practice_repository.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late PracticeRepository repository;
  late int root, child, grandchild, other, empty;
  late List<int> ownCards, allCards;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = PracticeRepository(db);
    final decks = DeckRepository(db);
    root = await decks.createDeck('操作系统');
    child = await decks.createDeck('进程', parentId: root);
    grandchild = await decks.createDeck('线程', parentId: child);
    other = await decks.createDeck('其他');
    empty = await decks.createDeck('空牌组');
    final notes = NoteRepository(db);
    for (var i = 0; i < 4; i++) {
      await notes.createBasicNote(deckId: root, front: '问题$i', back: '答案$i');
    }
    ownCards = (await db.select(db.cards).get()).map((c) => c.id).toList();
    await notes.createClozeNote(deckId: child, text: '{{c1::进程}}和{{c2::线程}}');
    await notes.createBasicNote(deckId: grandchild, front: '孙章节');
    allCards = (await db.select(db.cards).get()).map((c) => c.id).toList();
    await notes.createBasicNote(deckId: other, front: '无关卡片');
    // Future reviews must remain eligible, even if formal quotas are zero.
    await db
        .update(db.cards)
        .write(
          CardsCompanion(
            dueAtUtc: Value(DateTime.utc(2099).millisecondsSinceEpoch),
            state: const Value(2),
            stability: const Value(12),
            difficulty: const Value(4),
          ),
        );
    await StudyRepository(db).setFavorite(ownCards.first, true);
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(key: 'dailyNewLimit', valueJson: '0'),
        );
  });
  tearDown(() => db.close());

  test(
    'scope includes descendants only when requested; cloze cards stay distinct',
    () async {
      final direct = await repository.sample(
        deckId: root,
        includeChildren: false,
        count: 500,
      );
      expect(direct.deckName, '操作系统');
      expect(direct.cardIds, unorderedEquals(ownCards));
      final nested = await repository.sample(
        deckId: root,
        includeChildren: true,
        count: 500,
      );
      expect(nested.cardIds, unorderedEquals(allCards));
      expect(nested.cardIds.toSet().length, nested.cardIds.length);
      expect(() => nested.cardIds.add(999), throwsUnsupportedError);
    },
  );

  test('bounded sample is unique and empty deck returns no cards', () async {
    final sample = await repository.sample(
      deckId: root,
      includeChildren: true,
      count: 3,
    );
    expect(sample.cardIds.length, 3);
    expect(sample.cardIds.toSet().length, 3);
    expect(allCards, containsAll(sample.cardIds));
    expect(
      (await repository.sample(
        deckId: empty,
        includeChildren: true,
        count: 20,
      )).cardIds,
      isEmpty,
    );
  });

  test('rejects missing deck and out of range counts', () async {
    for (final count in [0, -1, 501]) {
      await expectLater(
        repository.sample(deckId: root, includeChildren: true, count: count),
        throwsArgumentError,
      );
    }
    await expectLater(
      repository.sample(deckId: -1, includeChildren: true, count: 20),
      throwsStateError,
    );
  });

  test(
    'sampling and reading a full round leave every stored row unchanged',
    () async {
      Future<List<Object?>> snapshot() async => [
        for (final table in [
          'cards',
          'notes',
          'decks',
          'favorites',
          'review_logs',
          'app_settings',
        ])
          (await db.customSelect('SELECT * FROM $table').get())
              .map((r) => r.data)
              .toList(),
      ];
      final before = await snapshot();
      final round = await repository.sample(
        deckId: root,
        includeChildren: true,
        count: 500,
      );
      for (final id in round.cardIds) {
        expect((await StudyRepository(db).getStudyCard(id)).card.id, id);
      }
      expect(await snapshot(), before);
    },
  );
}
