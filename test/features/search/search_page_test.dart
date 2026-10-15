import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/app/theme/app_theme.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/search/presentation/search_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late NoteRepository notes;
  late int deck;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    notes = NoteRepository(db);
    deck = await DeckRepository(db).createDeck('化学');
  });
  tearDown(() => db.close());
  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester, {bool narrow = false}) async {
    tester.view.physicalSize = narrow
        ? const Size(960, 2400)
        : const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    if (narrow) {
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: narrow ? AppTheme.dark : AppTheme.light,
          home: const SearchPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'current page selection clears on pagination and debounce; tag batch and cancelled delete preserve notes',
    (tester) async {
      await tester.runAsync(() async {
        for (var i = 0; i < 31; i++) {
          await notes.createBasicNote(deckId: deck, front: '问题 $i');
        }
      });
      await open(tester);
      await tap(tester, find.text('全选本页'));
      expect(find.text('已选 30 条笔记（仅当前页）'), findsOneWidget);
      await tap(tester, find.text('下一页'));
      expect(find.text('已选 0 条笔记（仅当前页）'), findsOneWidget);
      expect(find.text('第 2 页 · 本页 1 条笔记'), findsOneWidget);
      await tap(tester, find.text('全选本页'));
      await tap(tester, find.text('添加标签'));
      await tester.enterText(find.byType(TextField).last, '重点,复习');
      await tap(tester, find.text('确认'));
      expect(find.text('已处理 1 条笔记'), findsOneWidget);
      final last = await tester.runAsync(
        () async => (await db.select(db.notes).get()).last.id,
      );
      expect((await tester.runAsync(() => notes.getNote(last!)))!.tags, [
        '复习',
        '重点',
      ]);
      await tap(tester, find.text('全选本页'));
      await tap(tester, find.widgetWithText(OutlinedButton, '删除'));
      expect(find.textContaining('永久删除选中的 1 条笔记'), findsOneWidget);
      await tap(tester, find.text('取消'));
      expect(
        (await tester.runAsync(() => db.select(db.notes).get()))!.length,
        31,
      );
      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, '问题 1');
      await tester.pump();
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '删除'))
            .onPressed,
        isNull,
      );
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(find.text('已选 0 条笔记（仅当前页）'), findsOneWidget);
      expect(find.text('第 1 页 · 本页 11 条笔记'), findsOneWidget);
      await close(tester);
    },
  );
  testWidgets(
    'narrow dark large text supports favorite and type filtering without overflow',
    (tester) async {
      await tester.runAsync(() async {
        await notes.createClozeNote(deckId: deck, text: '{{c1::蓝色}}');
      });
      await open(tester, narrow: true);
      await tap(tester, find.text('仅看收藏笔记'));
      expect(find.text('没有匹配的笔记，请调整搜索或筛选。'), findsOneWidget);
      await tap(tester, find.text('仅看收藏笔记'));
      final type = find.byType(DropdownButtonFormField<int>).last;
      await tap(tester, type);
      await tap(tester, find.text('基础卡').last);
      expect(find.text('没有匹配的笔记，请调整搜索或筛选。'), findsOneWidget);
      await close(tester);
    },
  );
}
