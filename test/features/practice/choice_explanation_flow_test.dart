import 'dart:async';

import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/app/router/app_router.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/widgets/pressable_action.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_question.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/practice/data/practice_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class GatedPracticeRepository extends PracticeRepository {
  GatedPracticeRepository(super.db);
  Completer<void>? gate;

  @override
  Future<bool> submitChoice(
    int cardId,
    Set<int> selected, {
    required ChoiceQuestion expectedQuestion,
  }) async {
    await gate?.future;
    return super.submitChoice(
      cardId,
      selected,
      expectedQuestion: expectedQuestion,
    );
  }
}

void main() {
  const audioChannel = MethodChannel('com.cuso4.flashcards/audio');
  late AppDatabase db;
  late int deck;
  late ProviderContainer container;
  late GatedPracticeRepository practice;
  final longExplanation = List.generate(
    90,
    (i) => '<p>解析段落$i：这是用于验证长解析滚动与固定操作按钮的内容。</p>',
  ).join();
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, (_) async => null);
    db = AppDatabase(NativeDatabase.memory());
    deck = await DeckRepository(db).createDeck('解析测试');
    final notes = NoteRepository(db);
    await notes.createChoiceNote(
      deckId: deck,
      question: ChoiceQuestion(
        type: NoteType.singleChoice,
        prompt: '第一道题',
        options: ['错误甲', '正确乙', '错误丙'],
        correctIndexes: [1],
        explanation: longExplanation,
        shuffle: true,
      ),
    );
    await notes.createChoiceNote(
      deckId: deck,
      question: ChoiceQuestion(
        type: NoteType.multipleChoice,
        prompt: '第二道题',
        options: ['正确甲', '错误乙', '正确丙'],
        correctIndexes: [0, 2],
      ),
    );
    practice = GatedPracticeRepository(db);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        practiceRepositoryProvider.overrideWithValue(practice),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, null);
  });
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container, child: const Cuso4App()),
    );
    await tester.pumpAndSettle();
    container.read(appRouterProvider).go('/choice-practice/$deck');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('开始顺序练习'));
    await tester.tap(find.text('开始顺序练习'));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> choose(WidgetTester tester, int index) async {
    final option = find.byKey(ValueKey('choice-option-$index'));
    await tester.ensureVisible(option);
    await tester.tap(option);
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'slow saving cannot reveal early and returns to a locked answered question',
    (tester) async {
      await open(tester);
      await choose(tester, 0);
      practice.gate = Completer<void>();
      await tester.ensureVisible(find.text('提交答案'));
      await tester.tap(find.text('提交答案'));
      await tester.pump();
      expect(find.text('正在保存…'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('choice-explanation-page')),
        findsNothing,
      );
      practice.gate!.complete();
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('choice-explanation-page')),
        findsOneWidget,
      );
      await tap(tester, '返回题目');
      expect(find.text('回答错误'), findsOneWidget);
      expect(find.text('下一张'), findsOneWidget);
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('choice-option-1')))
            .onTap,
        isNull,
      );
      await close(tester);
    },
  );

  testWidgets(
    'submission opens explanation; fixed next and return preserve shuffled answers and one mistake',
    (tester) async {
      await open(tester);
      final beforeOrder = tester
          .widgetList<InkWell>(find.byType(InkWell))
          .where((w) => '${w.key}'.contains('choice-option'))
          .map((w) => w.key)
          .toList();
      await choose(tester, 0);
      await tap(tester, '提交答案');
      expect(
        find.byKey(const ValueKey('choice-explanation-page')),
        findsOneWidget,
      );
      expect(find.text('回答错误'), findsOneWidget);
      final correctLetter = String.fromCharCode(
        65 + beforeOrder.indexOf(const ValueKey('choice-option-1')),
      );
      expect(find.text('正确答案：$correctLetter'), findsOneWidget);
      final next = find.byKey(const ValueKey('explanation-next'));
      final firstPosition = tester.getCenter(next);
      expect(next.hitTestable(), findsOneWidget);
      final scroll = find.descendant(
        of: find.byKey(const ValueKey('choice-explanation-page')),
        matching: find.byType(SingleChildScrollView),
      );
      await tester.drag(scroll, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(tester.getCenter(next), firstPosition);
      expect(next.hitTestable(), findsOneWidget);
      expect(find.text('返回题目').hitTestable(), findsOneWidget);
      await tester.tap(find.text('返回题目'));
      await tester.pumpAndSettle();
      expect(find.text('第一道题', findRichText: true), findsOneWidget);
      expect(find.textContaining('解析段落0', findRichText: true), findsNothing);
      expect(
        tester
            .widgetList<InkWell>(find.byType(InkWell))
            .where((w) => '${w.key}'.contains('choice-option'))
            .map((w) => w.key),
        beforeOrder,
      );
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('choice-option-1')))
            .onTap,
        isNull,
      );
      await tap(tester, '查看解析');
      expect(find.text('回答错误'), findsOneWidget);
      expect(
        (await tester.runAsync(() => db.select(db.wrongQuestions).get()))!
            .single
            .wrongCount,
        1,
      );
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.physicalSize = const Size(1125, 2001);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('explanation-next')).hitTestable(),
        findsOneWidget,
      );
      tester.view.physicalSize = const Size(2001, 1125);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('explanation-next')).hitTestable(),
        findsOneWidget,
      );
      expect(find.text('返回题目').hitTestable(), findsOneWidget);
      final advance = tester
          .widget<PressableAction>(
            find.byKey(const ValueKey('explanation-next')),
          )
          .onPressed!;
      advance();
      advance();
      await tester.pumpAndSettle();
      expect(find.text('第二道题', findRichText: true), findsOneWidget);
      expect(
        find.byKey(const ValueKey('choice-explanation-page')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets(
    'view before submission is unattempted and original next still works; empty explanation completes last question',
    (tester) async {
      await open(tester);
      await choose(tester, 1);
      await tap(tester, '查看解析');
      expect(
        find.byKey(const ValueKey('choice-explanation-page')),
        findsOneWidget,
      );
      expect(find.text('未作答'), findsOneWidget);
      expect(
        (await tester.runAsync(() => db.select(db.wrongQuestions).get()))!,
        isEmpty,
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tap(tester, '下一张');
      await choose(tester, 0);
      await choose(tester, 2);
      await tap(tester, '提交答案');
      expect(find.text('回答正确'), findsOneWidget);
      expect(find.text('本题未提供解析'), findsOneWidget);
      expect(find.text('完成本轮').hitTestable(), findsOneWidget);
      await tester.tap(find.text('完成本轮'));
      await tester.pumpAndSettle();
      expect(find.text('本轮练习完成'), findsOneWidget);
      expect(find.text('答对 1 题 · 答错 0 题 · 未作答 1 题'), findsOneWidget);
      expect(
        (await tester.runAsync(() => db.select(db.reviewLogs).get()))!,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );
}
