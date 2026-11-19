import 'dart:convert';

import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/app/router/app_router.dart';
import 'package:cuso4_flashcards/core/content/card_content.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_question.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late ProviderContainer container;
  late int deck;
  const audio = MethodChannel('com.cuso4.flashcards/audio');
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audio, (_) async => null);
    db = AppDatabase(NativeDatabase.memory());
    deck = await DeckRepository(db).createDeck('字号牌组');
    final notes = NoteRepository(db);
    await notes.createBasicNote(deckId: deck, front: '阅读字号测试', back: '正文答案');
    await notes.createChoiceNote(
      deckId: deck,
      question: ChoiceQuestion(
        type: NoteType.singleChoice,
        prompt: '选择题字号测试',
        options: ['甲', '乙'],
        correctIndexes: [0],
        explanation: '解析字号测试',
      ),
    );
    container = ProviderContainer(
      overrides: [databaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audio, null);
  });
  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const Cuso4App()),
    );
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/settings');
    await tester.pumpAndSettle();
  }

  Future<void> scale(WidgetTester tester, String key, double percent) async {
    tester.widget<Slider>(find.byKey(ValueKey(key))).onChanged!(percent);
    await tester.pumpAndSettle();
  }

  double readingScale(WidgetTester tester, String source) {
    final card = find.byWidgetPredicate(
      (widget) => widget is CardContent && widget.source == source,
    );
    final rich = find
        .descendant(of: card, matching: find.byType(RichText))
        .first;
    return tester.widget<RichText>(rich).textScaler.scale(20);
  }

  testWidgets(
    'preview, independent scales, saved reentry, recitation and explanation, then reset',
    (tester) async {
      await open(tester);
      expect(find.text('字体大小'), findsOneWidget);
      await tap(tester, '字体大小');
      await scale(tester, 'ui-font-slider', 125);
      await scale(tester, 'card-font-slider', 150);
      expect(readingScale(tester, '卡片预览：题干、选项与解析会使用这一字号。'), 30);
      expect(
        (await tester.runAsync(
          () => db
              .customSelect(
                "SELECT * FROM app_settings WHERE key='fontSettings'",
              )
              .get(),
        ))!,
        isEmpty,
      );
      await tap(tester, '保存字号');
      final stored = (await tester.runAsync(
        () => db
            .customSelect(
              "SELECT value_json FROM app_settings WHERE key='fontSettings'",
            )
            .getSingle(),
      ))!;
      expect(jsonDecode(stored.read<String>('value_json')), {
        'uiPercent': 125,
        'cardPercent': 150,
      });
      expect(
        MediaQuery.textScalerOf(tester.element(find.text('保存字号'))).scale(20),
        25,
      );
      container.read(appRouterProvider).go('/recitation/$deck');
      await tester.pumpAndSettle();
      expect(readingScale(tester, '阅读字号测试'), 30);
      container.read(appRouterProvider).go('/choice-practice/$deck');
      await tester.pumpAndSettle();
      await tap(tester, '开始顺序练习');
      expect(readingScale(tester, '选择题字号测试'), 30);
      await tester.ensureVisible(find.byKey(const ValueKey('choice-option-0')));
      await tester.tap(find.byKey(const ValueKey('choice-option-0')));
      await tester.pumpAndSettle();
      await tap(tester, '提交答案');
      expect(readingScale(tester, '解析字号测试'), 30);
      expect(
        MediaQuery.textScalerOf(tester.element(find.text('完成本轮').first))
            .scale(20),
        25,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      container.dispose();
      container = ProviderContainer(
        overrides: [databaseProvider.overrideWithValue(db)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const Cuso4App(),
        ),
      );
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go('/font-settings');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('ui-font-slider')))
            .value,
        125,
      );
      expect(
        tester
            .widget<Slider>(find.byKey(const ValueKey('card-font-slider')))
            .value,
        150,
      );
      await tap(tester, '恢复默认');
      await tap(tester, '保存字号');
      expect(
        MediaQuery.textScalerOf(tester.element(find.text('保存字号'))).scale(20),
        20,
      );
      expect(readingScale(tester, '卡片预览：题干、选项与解析会使用这一字号。'), 20);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'default follows system and large text settings remain usable on small phone and landscape',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await open(tester);
      await tap(tester, '字体大小');
      expect(readingScale(tester, '卡片预览：题干、选项与解析会使用这一字号。'), 36);
      await scale(tester, 'ui-font-slider', 150);
      await scale(tester, 'card-font-slider', 200);
      tester.view.physicalSize = const Size(1125, 2001);
      await tap(tester, '保存字号');
      expect(readingScale(tester, '卡片预览：题干、选项与解析会使用这一字号。'), 72);
      tester.view.physicalSize = const Size(2001, 1125);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('恢复默认'));
      expect(find.text('恢复默认').hitTestable(), findsOneWidget);
      // Let the saved-confirmation snackbar expire before tapping the next
      // page: at very large UI text it temporarily covers bottom controls.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      container.read(appRouterProvider).go('/choice-practice/$deck');
      await tester.pumpAndSettle();
      await tap(tester, '开始顺序练习');
      await tap(tester, '查看解析');
      expect(find.text('返回题目').hitTestable(), findsOneWidget);
      expect(find.text('完成本轮').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
