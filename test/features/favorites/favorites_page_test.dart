import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:cuso4_flashcards/core/widgets/pressable_action.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const audioChannel = MethodChannel('com.cuso4.flashcards/audio');
  late AppDatabase db;
  late int cardId;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, (_) async => null);
    db = AppDatabase(NativeDatabase.memory());
    final deck = await DeckRepository(db).createDeck('操作系统');
    await NoteRepository(db)
        .createBasicNote(deckId: deck, front: '什么是进程？', back: '运行中的程序');
    cardId = (await db.select(db.cards).get()).single.id;
    await StudyRepository(db).setFavorite(cardId, true);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, null);
    await db.close();
  });

  Future<void> chooseDeck(WidgetTester tester, String name) async {
    await tester.ensureVisible(
      find.byKey(const ValueKey('favorite-deck-filter')),
    );
    await tester.tap(find.byKey(const ValueKey('favorite-deck-filter')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(name).last);
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<int> addFavorite(
    int deckId,
    String question, {
    bool favorite = true,
  }) async {
    final note = await NoteRepository(db)
        .createBasicNote(deckId: deckId, front: question, back: '练习答案');
    final card = await (db.select(
      db.cards,
    )..where((c) => c.noteId.equals(note))).getSingle();
    if (favorite) await StudyRepository(db).setFavorite(card.id, true);
    return card.id;
  }

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
    'deck scope includes children, resets on changes, preserves undo and handles deletion',
    (tester) async {
      final root = (await db.select(db.decks).get()).single.id;
      final child = await DeckRepository(db).createDeck('进程', parentId: root);
      final other = await DeckRepository(db).createDeck('计算机网络');
      await addFavorite(child, '子章节收藏');
      await addFavorite(other, '无关收藏');
      await open(tester);
      await chooseDeck(tester, '操作系统');
      expect(find.text('子章节收藏'), findsOneWidget);
      expect(find.text('无关收藏'), findsNothing);
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(find.text('子章节收藏'), findsNothing);
      expect(find.text('什么是进程？'), findsOneWidget);
      await tester.tap(find.byTooltip('取消收藏'));
      await tester.pumpAndSettle();
      expect(find.text('当前范围没有收藏卡片'), findsOneWidget);
      final action = tester.widget<PressableAction>(
        find.widgetWithText(PressableAction, '收藏随机练习'),
      );
      expect(action.onPressed, isNull);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(find.text('什么是进程？'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.runAsync(() => DeckRepository(db).deleteDeck(root));
      await tester.pumpAndSettle();
      expect(find.text('所选牌组已删除，请重新选择范围。'), findsOneWidget);
      expect(find.text('无关收藏'), findsNothing);
      await chooseDeck(tester, '全部牌组');
      expect(find.text('无关收藏'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'favorite practice spans every page and changing filters resets pagination',
    (tester) async {
      final other = await DeckRepository(db).createDeck('其他');
      for (var i = 0; i < 31; i++) {
        await addFavorite(other, '其他收藏$i');
      }
      await open(tester);
      await tester.ensureVisible(find.text('下一页'));
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 页'), findsOneWidget);
      await tester.ensureVisible(find.text('收藏随机练习'));
      await tester.tap(find.text('收藏随机练习'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始随机练习'));
      await tester.enterText(find.byType(TextFormField), '500');
      await tester.tap(find.text('开始随机练习'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 / 32 张'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('第 2 页'), findsOneWidget);
      await chooseDeck(tester, '操作系统');
      expect(find.text('第 2 页'), findsNothing);
      expect(find.byKey(ValueKey('favorite-card-$cardId')), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'favorite practice inherits exact scope and a completed round leaves data unchanged',
    (tester) async {
      final root = (await db.select(db.decks).get()).single.id;
      final child = await DeckRepository(db).createDeck('进程', parentId: root);
      await addFavorite(child, '子章节收藏');
      await addFavorite(root, '非收藏卡片', favorite: false);
      await open(tester);
      await chooseDeck(tester, '操作系统');
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
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
      final before = await tester.runAsync(snapshot);
      await tester.tap(find.text('收藏随机练习'));
      await tester.pumpAndSettle();
      expect(find.text('仅练习收藏卡片'), findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse,
      );
      await tester.ensureVisible(find.text('开始随机练习'));
      await tester.tap(find.text('开始随机练习'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 / 1 张'), findsOneWidget);
      expect(find.text('什么是进程？', findRichText: true), findsOneWidget);
      expect(find.text('非收藏卡片', findRichText: true), findsNothing);
      await tester.tap(find.text('显示答案'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('完成本轮'));
      await tester.pumpAndSettle();
      expect(find.text('已练习 1 张'), findsOneWidget);
      expect(await tester.runAsync(snapshot), before);
      // Another round must see newly removed favorites rather than stale IDs.
      await tester.runAsync(
        () => StudyRepository(db).setFavorite(cardId, false),
      );
      await tester.tap(find.text('再练一轮'));
      await tester.pumpAndSettle();
      expect(find.text('当前范围没有收藏卡片。可调整章节范围，或先收藏卡片。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'long chapter paths remain selectable with large dark text and landscape',
    (tester) async {
      const parentName = '计算机基础与操作系统知识点汇总（第一册）';
      const childName = '进程与线程的调度和同步';
      final parent = await DeckRepository(db).createDeck(parentName);
      final child = await DeckRepository(db)
          .createDeck(childName, parentId: parent);
      await addFavorite(child, '长路径收藏');
      await db
          .into(db.appSettings)
          .insert(AppSettingsCompanion.insert(key: 'theme', valueJson: 'dark'));
      await open(tester);
      tester.view.physicalSize = const Size(1125, 2001);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpAndSettle();
      await chooseDeck(tester, '$parentName / $childName');
      expect(find.text('长路径收藏'), findsOneWidget);
      expect(find.text('什么是进程？'), findsNothing);
      tester.view.physicalSize = const Size(2001, 1125);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('收藏随机练习'));
      await tester.tap(find.text('收藏随机练习'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始随机练习'));
      await tester.tap(find.text('开始随机练习'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 / 1 张'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

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
