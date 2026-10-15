import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/widgets/pressable_action.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/home/application/home_summary_service.dart';
import 'package:cuso4_flashcards/features/home/domain/home_summary.dart';
import 'package:cuso4_flashcards/features/settings/data/study_settings_repository.dart';
import 'package:cuso4_flashcards/features/settings/domain/study_settings.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FallibleHomeService extends HomeSummaryService {
  FallibleHomeService(super.db, {super.study});
  bool fail = false;
  int loads = 0;
  @override
  Future<HomeSummary> load() {
    loads++;
    return fail ? Future.error(StateError('测试读取失败')) : super.load();
  }
}

void main() {
  late AppDatabase db;
  late FallibleHomeService service;
  late DateTime now;
  late StudyRepository study;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 15, 8);
    study = StudyRepository(
      db,
      clock: () => now,
      timezoneOffset: () => const Duration(hours: 8),
    );
    service = FallibleHomeService(db, study: study);
  });
  tearDown(() => db.close());

  Future<int> seed({Duration dueIn = Duration.zero}) async {
    final deck = await DeckRepository(db).createDeck('操作系统');
    await NoteRepository(db)
        .createBasicNote(deckId: deck, front: '进程', back: '运行中的程序');
    await db
        .update(db.cards)
        .write(
          CardsCompanion(
            dueAtUtc: Value(now.add(dueIn).millisecondsSinceEpoch),
          ),
        );
    return deck;
  }

  Future<void> open(
    WidgetTester tester, {
    Map<String, String> settings = const {},
  }) async {
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          homeSummaryServiceProvider.overrideWithValue(service),
          studyRepositoryProvider.overrideWithValue(study),
          settingsProvider.overrideWith((ref) => Stream.value(settings)),
        ],
        child: const Cuso4App(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> click(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'homepage shows real counts and refreshes after rating and undo',
    (tester) async {
      await seed();
      await open(tester);
      expect(find.bySemanticsLabel('现在可学，1 张'), findsOneWidget);
      expect(find.bySemanticsLabel('可学新卡，1 张'), findsOneWidget);
      expect(find.text('今日已学 0 张'), findsOneWidget);
      await click(tester, find.text('开始今日学习'));
      await click(tester, find.text('显示答案'));
      await click(tester, find.textContaining('良好').first);
      await click(tester, find.byTooltip('退出学习'));
      expect(find.text('今日已学 1 张'), findsOneWidget);
      expect(find.text('已评分 1 次 · 当前连续 1 天'), findsOneWidget);
      final row = (await db.select(db.reviewLogs).get()).single;
      await tester.runAsync(() => study.undoReview(row.id));
      await tester.pumpAndSettle();
      expect(find.text('今日已学 0 张'), findsOneWidget);
      expect(find.bySemanticsLabel('现在可学，1 张'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets('empty homepage has working import and first-card paths', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('先放入你的第一张卡片'), findsOneWidget);
    await click(tester, find.text('导入 .apkg 牌组'));
    expect(find.textContaining('选择').first, findsWidgets);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await click(tester, find.text('新建第一张卡片'));
    await tester.enterText(find.byType(TextField), '我的笔记');
    await click(tester, find.text('保存'));
    expect(find.text('新建卡片'), findsOneWidget);
    expect((await db.select(db.decks).get()).single.name, '我的笔记');
    await close(tester);
  });

  testWidgets(
    'quota and future-due states disable study without claiming all complete',
    (tester) async {
      await seed();
      await StudySettingsRepository(db).save(StudySettings(dailyNewLimit: 0));
      await open(tester);
      expect(find.textContaining('今日额度限制'), findsOneWidget);
      var action = tester.widget<PressableAction>(
        find.widgetWithText(PressableAction, '暂时没有可学卡片'),
      );
      expect(action.onPressed, isNull);
      await tester.runAsync(
        () => StudySettingsRepository(db).save(StudySettings()),
      );
      await tester.runAsync(
        () => db
            .update(db.cards)
            .write(
              CardsCompanion(
                dueAtUtc: Value(
                  now.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
                ),
              ),
            ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('下次到期：10月15日 16:02'), findsOneWidget);
      final before = service.loads;
      now = now.add(const Duration(minutes: 2, seconds: 2));
      await tester.pump(const Duration(minutes: 2, seconds: 2));
      await tester.pumpAndSettle();
      expect(service.loads, greaterThan(before));
      expect(find.bySemanticsLabel('现在可学，1 张'), findsOneWidget);
      action = tester.widget<PressableAction>(
        find.widgetWithText(PressableAction, '开始今日学习'),
      );
      expect(action.onPressed, isNotNull);
      await close(tester);
    },
  );

  testWidgets('failure can retry, resume and midnight refresh learning day', (
    tester,
  ) async {
    now = DateTime.utc(2026, 10, 31, 15, 59, 59);
    await seed();
    service.fail = true;
    await open(tester);
    expect(find.text('测试读取失败'), findsOneWidget);
    service.fail = false;
    await click(tester, find.text('重新读取今日概览'));
    expect(find.text('10月31日 · 今日'), findsOneWidget);
    now = DateTime.utc(2026, 10, 31, 16, 0, 2);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('11月1日 · 今日'), findsOneWidget);
    final before = service.loads;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(service.loads, greaterThan(before));
    expect(await db.select(db.appSettings).get(), isEmpty);
    await close(tester);
  });

  testWidgets(
    'root deck preview navigates; target, small, dark and large text stay usable',
    (tester) async {
      final root = await DeckRepository(db).createDeck('很长的操作系统牌组名称用于验证自动换行');
      final child = await DeckRepository(db).createDeck('第一章', parentId: root);
      await NoteRepository(db)
          .createBasicNote(deckId: child, front: '线程', back: '执行单元');
      await db
          .update(db.cards)
          .write(CardsCompanion(dueAtUtc: Value(now.millisecondsSinceEpoch)));
      await open(tester, settings: {'theme': 'dark'});
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
        ThemeMode.dark,
      );
      expect(find.text('1 张卡片 · 含子章节'), findsOneWidget);
      expect(find.text('第一章'), findsNothing);
      for (final size in [
        const Size(320, 740),
        const Size(375, 812),
        const Size(904, 407),
        const Size(1024, 768),
      ]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        tester.platformDispatcher.accessibilityFeaturesTestValue =
            const FakeAccessibilityFeatures(disableAnimations: true);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('开始今日学习'));
        final actionSize = tester.getSize(
          find.widgetWithText(PressableAction, '开始今日学习'),
        );
        expect(actionSize.height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      }
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await tester.pumpAndSettle();
      await click(tester, find.text('很长的操作系统牌组名称用于验证自动换行'));
      expect(find.text('学习这个牌组'), findsOneWidget);
      await close(tester);
    },
  );
}
