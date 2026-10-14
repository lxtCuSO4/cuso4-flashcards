import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/favorites/data/favorite_repository.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late FavoriteRepository favorites;
  late StudyRepository study;
  late int basicId;
  late int clozeNote;
  late List<int> clozeIds;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    favorites = FavoriteRepository(db);
    study = StudyRepository(db, clock: () => DateTime.utc(2026, 10, 15));
    final decks = DeckRepository(db);
    final root = await decks.createDeck('操作系统');
    final child = await decks.createDeck('进程', parentId: root);
    final notes = NoteRepository(db);
    final basic = await notes.createBasicNote(
      deckId: root,
      front: '<b>什么是进程？</b>',
      back: '运行中的程序',
    );
    basicId = (await (db.select(
      db.cards,
    )..where((c) => c.noteId.equals(basic))).get()).single.id;
    clozeNote = await notes.createClozeNote(
      deckId: child,
      text: '{{c1::进程}}与{{c2::线程}}',
    );
    clozeIds =
        (await (db.select(
              db.cards,
            )..where((c) => c.noteId.equals(clozeNote))).get())
            .map((c) => c.id)
            .toList();
    await notes.createBasicNote(deckId: child, front: '尚未收藏', back: '不展示');
    for (final id in [basicId, ...clozeIds]) {
      await study.setFavorite(id, true);
    }
  });
  tearDown(() => db.close());

  test(
    'stable bounded pages contain only favorites and independent cloze cards',
    () async {
      final first = await favorites.watchPage(limit: 2).first;
      expect(first.items.map((e) => e.cardId), clozeIds.reversed);
      expect(first.hasNext, isTrue);
      expect(first.items.map((e) => e.preview), ['进程与[…]', '[…]与线程']);
      expect(first.items.every((e) => e.deckName == '进程'), isTrue);
      final last = await favorites.watchPage(limit: 2, offset: 2).first;
      expect(last.items.single.cardId, basicId);
      expect(last.items.single.preview, '什么是进程？');
      expect(last.hasNext, isFalse);
    },
  );

  test('rejects unbounded or invalid paging parameters', () {
    expect(() => favorites.watchPage(limit: 0), throwsArgumentError);
    expect(() => favorites.watchPage(limit: 31), throwsArgumentError);
    expect(() => favorites.watchPage(offset: -1), throwsArgumentError);
  });

  test(
    'preview, cancel and restore leave all scheduling and logs unchanged',
    () async {
      final before = (await db.select(db.cards).get())
          .map((c) => c.toJson())
          .toList();
      await study.getStudyCard(basicId);
      await favorites.watchPage().first;
      await study.setFavorite(basicId, false);
      expect(
        (await favorites.watchPage().first).items.map((e) => e.cardId),
        isNot(contains(basicId)),
      );
      await study.setFavorite(basicId, true);
      expect(
        (await favorites.watchPage().first).items.map((e) => e.cardId),
        contains(basicId),
      );
      expect(
        (await db.select(db.cards).get()).map((c) => c.toJson()).toList(),
        before,
      );
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      expect(await db.select(db.appSettings).get(), isEmpty);
    },
  );

  test(
    'deleting a note cascades its favorites without removing other cards',
    () async {
      await NoteRepository(db).deleteNote(clozeNote);
      final page = await favorites.watchPage().first;
      expect(page.items.single.cardId, basicId);
      expect((await db.select(db.favorites).get()).single.cardId, basicId);
    },
  );
}
