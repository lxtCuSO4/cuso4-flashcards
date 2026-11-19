import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/app/router/app_router.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_question.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/decks/presentation/choice_card_face.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dart:convert';

void main() {
  const audio = MethodChannel('com.cuso4.flashcards/audio');
  late AppDatabase db;
  late ProviderContainer container;
  late int deck;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audio, (_) async => null);
    db = AppDatabase(NativeDatabase.memory());
    deck = await DeckRepository(db).createDeck('续练牌组');
    for (var i = 0; i < 2; i++) {
      await NoteRepository(db).createChoiceNote(
        deckId: deck,
        question: ChoiceQuestion(
          type: NoteType.singleChoice,
          prompt: '续练问题$i',
          options: ['正确', '错误'],
          correctIndexes: [0],
          shuffle: true,
        ),
      );
    }
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
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> reenter(WidgetTester tester) async {
    final before = await tester.runAsync(
      () async => (await db.select(db.appSettings).get())
          .where((s) => s.key.endsWith(':cursor'))
          .map((s) => (jsonDecode(s.valueJson) as Map)..remove('elapsedMs'))
          .toList(),
    );
    container.read(appRouterProvider).go('/');
    await tester.pumpAndSettle();
    final after = await tester.runAsync(
      () async => (await db.select(db.appSettings).get())
          .where((s) => s.key.endsWith(':cursor'))
          .map((s) => (jsonDecode(s.valueJson) as Map)..remove('elapsedMs'))
          .toList(),
    );
    expect(
      after,
      before,
      reason: 'Leaving the whole practice must keep its view state',
    );
    container.read(appRouterProvider).go('/choice-practice/$deck');
    await tester.pumpAndSettle();
    await tap(tester, '继续顺序练习');
  }

  testWidgets('practice needs no quantity input', (tester) async {
    await open(tester);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('练习张数'), findsNothing);
    expect(find.text('开始顺序练习'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving an unanswered question saves foreground time', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, '开始顺序练习');
    container.read(appRouterProvider).go('/');
    await tester.pumpAndSettle();
    final cursor = await tester.runAsync(
      () async => jsonDecode(
        (await db.select(db.appSettings).get())
            .singleWhere((s) => s.key.endsWith(':cursor'))
            .valueJson,
      ) as Map,
    );
    expect(cursor!['elapsedMs'], greaterThan(0));
    expect(cursor['attempted'], false);
  });

  testWidgets(
    'selected options and their order restore after leaving practice',
    (tester) async {
      await open(tester);
      await tap(tester, '开始顺序练习');
      final originalOrder = tester
          .widget<ChoiceCardFace>(find.byType(ChoiceCardFace))
          .initialAttempt!
          .order;
      await tester.tap(find.byKey(const ValueKey('choice-option-1')));
      await tester.pumpAndSettle();
      await reenter(tester);
      final restored = tester
          .widget<ChoiceCardFace>(find.byType(ChoiceCardFace))
          .initialAttempt!;
      expect(restored.selected, {1});
      expect(restored.order, originalOrder);
      expect(restored.attempted, false);
      expect(find.text('第 1 / 2 张'), findsOneWidget);
    },
  );

  testWidgets(
    'submitted explanation restores and tag editing keeps the answer locked',
    (tester) async {
      await open(tester);
      await tap(tester, '开始顺序练习');
      await tester.tap(find.byKey(const ValueKey('choice-option-1')));
      await tester.pumpAndSettle();
      await tap(tester, '提交答案');
      expect(find.text('回答错误'), findsOneWidget);
      await reenter(tester);
      expect(find.text('回答错误'), findsOneWidget);
      expect(
        (await tester.runAsync(() => db.select(db.wrongQuestions).get()))!
            .single
            .wrongCount,
        1,
      );
      await tap(tester, '返回题目');
      await tester.tap(find.byTooltip('编辑卡片'));
      await tester.pumpAndSettle();
      final tags = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '标签',
      );
      await tester.ensureVisible(tags);
      await tester.enterText(tags, '新增标签');
      await tap(tester, '保存卡片');
      final restored = tester
          .widget<ChoiceCardFace>(find.byType(ChoiceCardFace))
          .initialAttempt!;
      expect(restored.attempted, true);
      expect(restored.selected, {1});
      expect(find.text('下一张'), findsOneWidget);
      await tap(tester, '下一张');
      expect(find.text('第 2 / 2 张'), findsOneWidget);
      await reenter(tester);
      expect(find.text('第 2 / 2 张'), findsOneWidget);
      expect(
        (await tester.runAsync(() => db.select(db.wrongQuestions).get()))!
            .single
            .wrongCount,
        1,
      );
    },
  );

  testWidgets('editing question content resets only its answer', (
    tester,
  ) async {
    await open(tester);
    await tap(tester, '开始顺序练习');
    await tester.tap(find.byKey(const ValueKey('choice-option-1')));
    await tester.pumpAndSettle();
    await tap(tester, '提交答案');
    await tap(tester, '返回题目');
    await tester.tap(find.byTooltip('编辑卡片'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('note-front')), '修改后的题干');
    await tap(tester, '保存卡片');
    final restored = tester
        .widget<ChoiceCardFace>(find.byType(ChoiceCardFace))
        .initialAttempt!;
    expect(restored.attempted, false);
    expect(restored.selected, isEmpty);
    expect(find.text('第 1 / 2 张'), findsOneWidget);
    expect(find.text('修改后的题干', findRichText: true), findsOneWidget);
  });
}
