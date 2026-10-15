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
    'fixed decorations ignore legacy opt-out across pages and app restarts',
    (tester) async {
      tester.view.physicalSize = const Size(1220, 2712);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'touhouDecorations',
              valueJson: 'false',
            ),
          );
      await open(tester);
      expect(find.text('寺子屋'), findsOneWidget);
      await go(tester, '/decks');
      expect(find.text('寺子屋 · 藏书'), findsOneWidget);
      await go(tester, '/decks/$deck');
      expect(find.text('寺子屋 · 藏书'), findsOneWidget);
      await go(tester, '/practice/$deck');
      expect(find.text('迷途竹林'), findsOneWidget);
      await go(tester, '/records');
      expect(find.text('月下手记'), findsOneWidget);
      await go(tester, '/favorites');
      expect(find.text('铃仙的书签'), findsOneWidget);
      await go(tester, '/favorite-practice');
      expect(find.text('铃仙的书签'), findsOneWidget);
      await go(tester, '/study?deckId=$deck');
      expect(find.text('寺子屋 · 温习'), findsOneWidget);
      await go(tester, '/settings');
      expect(find.text('永远亭'), findsOneWidget);
      expect(find.text('东方主题装饰'), findsNothing);
      expect(find.byType(SwitchListTile), findsNothing);
      await close(tester);
      await db
          .into(db.appSettings)
          .insert(AppSettingsCompanion.insert(key: 'theme', valueJson: 'dark'));
      tester.view.physicalSize = const Size(1125, 2436);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await open(tester);
      expect(find.text('寺子屋'), findsOneWidget);
      expect(find.text('导入 .apkg 牌组'), findsOneWidget);
      await go(tester, '/practice/$deck');
      expect(find.text('迷途竹林'), findsOneWidget);
      expect(find.text('开始随机练习'), findsOneWidget);
      await go(tester, '/settings');
      expect(find.text('永远亭'), findsOneWidget);
      expect(find.text('东方主题装饰'), findsNothing);
      expect(
        (await (db.select(
              db.appSettings,
            )..where((s) => s.key.equals('touhouDecorations'))).getSingle())
            .valueJson,
        'false',
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(2436, 1125);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );
}
