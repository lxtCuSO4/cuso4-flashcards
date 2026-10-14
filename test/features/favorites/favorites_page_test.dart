import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late int cardId;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final deck = await DeckRepository(db).createDeck('操作系统');
    await NoteRepository(db)
        .createBasicNote(deckId: deck, front: '什么是进程？', back: '运行中的程序');
    cardId = (await db.select(db.cards).get()).single.id;
    await StudyRepository(db).setFavorite(cardId, true);
  });
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const Cuso4App(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录').last);
    await tester.pumpAndSettle();
    expect(find.text('查看收藏'), findsOneWidget);
    await tester.tap(find.text('查看收藏'));
    await tester.pumpAndSettle();
  }

  testWidgets('record entry opens a read-only preview with answer gating', (
    tester,
  ) async {
    await open(tester);
    final before = await tester.runAsync(
      () async => (await db.select(db.cards).get()).single.toJson(),
    );
    await tester.tap(find.byKey(ValueKey('favorite-card-$cardId')));
    await tester.pumpAndSettle();
    expect(find.text('仅预览，不修改学习进度'), findsOneWidget);
    expect(find.text('运行中的程序'), findsNothing);
    await tester.tap(find.text('显示答案'));
    await tester.pumpAndSettle();
    expect(find.text('运行中的程序'), findsOneWidget);
    expect(find.byKey(const ValueKey('rating-good')), findsNothing);
    await tester.runAsync(() async {
      expect((await db.select(db.cards).get()).single.toJson(), before);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      expect(await db.select(db.appSettings).get(), isEmpty);
    });
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'cancel favorite updates the list and offers undo without losing the card',
    (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('取消收藏'));
      await tester.pumpAndSettle();
      expect(find.text('还没有收藏卡片'), findsOneWidget);
      expect(find.text('已取消收藏'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(find.text('什么是进程？'), findsOneWidget);
      await tester.runAsync(() async {
        expect((await db.select(db.cards).get()).single.id, cardId);
        expect((await db.select(db.favorites).get()).single.cardId, cardId);
        expect(await db.select(db.reviewLogs).get(), isEmpty);
      });
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets('undo remains safe after leaving the favorite list', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('取消收藏'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('查看收藏'), findsOneWidget);
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      expect((await db.select(db.favorites).get()).single.cardId, cardId);
    });
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'pagination stays bounded and an emptied final page can return to the previous page',
    (tester) async {
      await tester.runAsync(() async {
        final deck = (await db.select(db.decks).get()).single.id;
        for (var i = 0; i < 30; i++) {
          final note = await NoteRepository(db)
              .createBasicNote(deckId: deck, front: '其他收藏 $i');
          final card = (await (db.select(
            db.cards,
          )..where((c) => c.noteId.equals(note))).get()).single;
          await StudyRepository(db).setFavorite(card.id, true);
        }
      });
      await open(tester);
      expect(find.byType(ListTile), findsNWidgets(30));
      expect(find.text('什么是进程？'), findsNothing);
      await tester.ensureVisible(find.text('下一页'));
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('什么是进程？'), findsOneWidget);
      expect(find.byType(ListTile), findsOneWidget);
      await tester.ensureVisible(find.byTooltip('取消收藏'));
      await tester.tap(find.byTooltip('取消收藏'));
      await tester.pumpAndSettle();
      expect(find.text('本页暂无收藏'), findsOneWidget);
      await tester.ensureVisible(find.text('上一页'));
      await tester.tap(find.text('上一页'));
      await tester.pumpAndSettle();
      expect(find.byType(ListTile), findsNWidgets(30));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'small phone, large text, dark mode and landscape stay operable',
    (tester) async {
      await open(tester);
      tester.view.physicalSize = const Size(1125, 2001);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(ValueKey('favorite-card-$cardId')));
      await tester.pumpAndSettle();
      tester.view.physicalSize = const Size(2001, 1125);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('显示答案'));
      await tester.tap(find.text('显示答案'));
      await tester.pumpAndSettle();
      expect(find.text('运行中的程序'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
