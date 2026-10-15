import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/app/router/app_router.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late int deck;
  ProviderContainer? container;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    deck = await DeckRepository(db).createDeck('操作系统');
  });
  tearDown(() async {
    container?.dispose();
    container = null;
    await db.close();
  });

  Future<void> open(WidgetTester tester) async {
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container!, child: const Cuso4App()),
    );
    await tester.pumpAndSettle();
  }

  Future<void> go(WidgetTester tester, String path) async {
    container!.read(appRouterProvider).go(path);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    container?.dispose();
    container = null;
    await tester.pumpAndSettle();
  }

  testWidgets(
    'decoration switch persists across app restart and updates themed pages',
    (tester) async {
      tester.view.physicalSize = const Size(1220, 2712);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await open(tester);
      expect(find.text('寺子屋'), findsOneWidget);
      await go(tester, '/decks');
      expect(find.text('寺子屋 · 藏书'), findsOneWidget);
      await go(tester, '/practice/$deck');
      expect(find.text('迷途竹林'), findsOneWidget);
      await go(tester, '/records');
      expect(find.text('月下手记'), findsOneWidget);
      await go(tester, '/favorites');
      expect(find.text('铃仙的书签'), findsOneWidget);
      await go(tester, '/settings');
      expect(find.text('永远亭'), findsOneWidget);
      final toggle = find.text('东方主题装饰');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('永远亭'), findsNothing);
      expect(
        (await (db.select(
              db.appSettings,
            )..where((s) => s.key.equals('touhouDecorations'))).getSingle())
            .valueJson,
        'false',
      );
      await close(tester);
      await open(tester);
      expect(find.text('寺子屋'), findsNothing);
      expect(find.text('导入 .apkg 牌组'), findsOneWidget);
      await go(tester, '/practice/$deck');
      expect(find.text('迷途竹林'), findsNothing);
      expect(find.text('开始随机练习'), findsOneWidget);
      await go(tester, '/settings');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('永远亭'), findsOneWidget);
      await go(tester, '/');
      expect(find.text('寺子屋'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets(
    'failed setting save keeps decorations on in dark large-text layouts',
    (tester) async {
      tester.view.physicalSize = const Size(1125, 2436);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await db
          .into(db.appSettings)
          .insert(AppSettingsCompanion.insert(key: 'theme', valueJson: 'dark'));
      await db.customStatement(
        "CREATE TRIGGER fail_decoration BEFORE INSERT ON app_settings WHEN NEW.key = 'touhouDecorations' BEGIN SELECT RAISE(FAIL, 'write failed'); END",
      );
      await open(tester);
      await go(tester, '/settings');
      final toggle = find.text('东方主题装饰');
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(find.text('永远亭'), findsOneWidget);
      expect(find.text('操作未完成，请重试。'), findsOneWidget);
      expect(
        (await (db.select(
          db.appSettings,
        )..where((s) => s.key.equals('touhouDecorations'))).get()),
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(2436, 1125);
      await tester.pumpAndSettle();
      await tester.ensureVisible(toggle);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );
}
