import 'dart:ui' show SemanticsAction;

import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/records/data/statistics_repository.dart';
import 'package:cuso4_flashcards/features/records/domain/daily_statistics.dart';
import 'package:cuso4_flashcards/features/records/presentation/learning_calendar.dart';
import 'package:cuso4_flashcards/features/records/presentation/statistics_charts.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FallibleStatistics extends StatisticsRepository {
  FallibleStatistics(super.db, {super.clock, super.timezoneOffset});
  bool fail = false;
  @override
  Future<StatisticsSnapshot> load({
    StatisticsPeriod period = StatisticsPeriod.week,
    DateTime? month,
  }) {
    if (fail) return Future.error(StateError('测试读取失败'));
    return super.load(period: period, month: month);
  }
}

void main() {
  late AppDatabase db;
  late FallibleStatistics repository;
  late DateTime now;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 10, 15, 8);
    repository = FallibleStatistics(
      db,
      clock: () => now,
      timezoneOffset: () => const Duration(hours: 8),
    );
  });
  tearDown(() => db.close());

  Future<void> seed() async {
    final deck = await DeckRepository(db).createDeck('操作系统');
    await NoteRepository(db)
        .createBasicNote(deckId: deck, front: '进程', back: '运行中的程序');
    final card = (await db.select(db.cards).get()).single.id;
    for (final (ago, rating, seconds) in [(0, 1, 5), (0, 3, 7), (20, 4, 1)]) {
      await db
          .into(db.reviewLogs)
          .insert(
            ReviewLogsCompanion.insert(
              cardId: card,
              reviewedAtUtc: now
                  .subtract(Duration(days: ago))
                  .millisecondsSinceEpoch,
              rating: rating,
              elapsedMilliseconds: seconds * 1000,
              beforeStateJson: '{}',
              afterStateJson: '{}',
            ),
          );
    }
  }

  Future<void> open(WidgetTester tester) async {
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
          statisticsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const Cuso4App(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('记录').last);
    await tester.pumpAndSettle();
  }

  Future<void> click(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder summaryText(String text) => find.descendant(
    of: find.byType(StatisticsSummary).first,
    matching: find.text(text),
  );
  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'range, calendar day details and month navigation use actual logs',
    (tester) async {
      await seed();
      await open(tester);
      expect(summaryText('2 次'), findsOneWidget);
      expect(summaryText('1 张'), findsOneWidget);
      expect(summaryText('12 秒'), findsOneWidget);
      expect(summaryText('50.0%'), findsOneWidget);
      await click(tester, find.byKey(const ValueKey('statistics-month')));
      expect(summaryText('3 次'), findsOneWidget);
      await click(tester, find.byKey(const ValueKey('statistics-week')));
      final today = find.byKey(const ValueKey('calendar-2026-10-15'));
      await tester.ensureVisible(today);
      final semantics = tester.ensureSemantics();
      try {
        expect(
          tester
              .getSemantics(find.bySemanticsLabel('2026年10月15日，学习 2 次，今天'))
              .getSemanticsData()
              .hasAction(SemanticsAction.tap),
          isTrue,
        );
      } finally {
        semantics.dispose();
      }
      expect(tester.getSize(today).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(today).height, greaterThanOrEqualTo(48));
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('calendar-2026-10-16')))
            .onTap,
        isNull,
      );
      await click(tester, today);
      expect(find.text('2026年10月15日'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('12 秒'),
        ),
        findsOneWidget,
      );
      await click(tester, find.byTooltip('关闭日期详情'));
      await click(tester, find.byTooltip('上个月'));
      expect(find.text('2026年9月'), findsOneWidget);
      expect(summaryText('2 次'), findsOneWidget);
      await click(tester, find.byKey(const ValueKey('calendar-2026-9-25')));
      expect(
        find.descendant(
          of: find.byType(BottomSheet),
          matching: find.text('1 次'),
        ),
        findsWidgets,
      );
      await click(tester, find.byTooltip('关闭日期详情'));
      await click(tester, find.text('回到本月'));
      expect(find.text('2026年10月'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets(
    'empty days show no invented success rate and preserve the favorites entry',
    (tester) async {
      await open(tester);
      expect(summaryText('0 次'), findsOneWidget);
      expect(summaryText('—'), findsOneWidget);
      await click(tester, find.byKey(const ValueKey('calendar-2026-10-14')));
      expect(find.text('这一天还没有学习记录。'), findsOneWidget);
      await click(tester, find.byTooltip('关闭日期详情'));
      await click(tester, find.text('查看收藏'));
      expect(find.text('还没有收藏卡片'), findsOneWidget);
      expect(
        await tester.runAsync(() => db.select(db.appSettings).get()),
        isEmpty,
      );
      await close(tester);
    },
  );

  testWidgets(
    'read failure can retry; returning to foreground refreshes the date',
    (tester) async {
      repository.fail = true;
      await open(tester);
      expect(find.text('测试读取失败'), findsOneWidget);
      repository.fail = false;
      await click(tester, find.text('重新读取记录'));
      expect(find.byType(LearningCalendar), findsOneWidget);
      now = DateTime.utc(2026, 11, 1, 8);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('2026年11月'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets('midnight refresh works without leaving the page', (
    tester,
  ) async {
    now = DateTime.utc(2026, 10, 31, 15, 59, 58);
    await seed();
    await open(tester);
    expect(find.text('2026年10月'), findsOneWidget);
    await click(tester, find.byKey(const ValueKey('calendar-2026-10-31')));
    now = DateTime.utc(2026, 10, 31, 16, 0, 2);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('2026年11月'), findsOneWidget);
    expect(
      find.descendant(of: find.byType(BottomSheet), matching: find.text('2 次')),
      findsOneWidget,
    );
    await click(tester, find.byTooltip('关闭日期详情'));
    await close(tester);
  });

  testWidgets(
    'small phone, large text, dark, landscape and day sheet remain usable',
    (tester) async {
      await seed();
      await open(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      for (final size in [
        const Size(960, 1800),
        const Size(2712, 1220),
        const Size(2304, 3072),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        await click(tester, find.byKey(const ValueKey('calendar-2026-10-15')));
        await click(tester, find.byTooltip('关闭日期详情'));
        await tester.ensureVisible(find.text('统计口径'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await close(tester);
    },
  );
}
