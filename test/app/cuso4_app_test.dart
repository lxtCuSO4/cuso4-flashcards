import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:drift/native.dart';

void main() {
  testWidgets('shows Lunar Memory with Material 3 and both themes', (
    tester,
  ) async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          decksProvider.overrideWith((ref) => Stream.value([])),
          cardCountsProvider.overrideWith((ref) => Stream.value({})),
          settingsProvider.overrideWith((ref) => Stream.value({})),
        ],
        child: const Cuso4App(),
      ),
    );
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'Lunar Memory');
    expect(app.theme!.useMaterial3, isTrue);
    expect(app.darkTheme!.brightness, Brightness.dark);
    expect(app.themeMode, ThemeMode.system);
    expect(find.text('Lunar Memory'), findsOneWidget);
    expect(find.byType(SafeArea), findsWidgets);
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
    expect(find.text('新建牌组'), findsOneWidget);
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(3072, 2304);
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
