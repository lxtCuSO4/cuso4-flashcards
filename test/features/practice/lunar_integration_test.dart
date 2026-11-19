import 'dart:io';
import 'dart:ui' as ui;

import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/app/router/app_router.dart';
import 'package:cuso4_flashcards/app/theme/app_theme.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_question.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
import 'package:cuso4_flashcards/features/decks/presentation/choice_card_face.dart';
import 'package:cuso4_flashcards/features/practice/presentation/choice_practice_scaffold.dart';
import 'package:cuso4_flashcards/features/settings/data/font_settings_repository.dart';
import 'package:cuso4_flashcards/features/settings/domain/font_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // Readable local evidence only; these host fonts are not bundled in the app.
    for (final entry in {
      'Roboto': 'C:/Windows/Fonts/msyh.ttc',
      'Ahem': 'C:/Windows/Fonts/msyh.ttc',
      'serif': 'C:/Windows/Fonts/simsun.ttc',
      'MaterialIcons': 'D:/dev/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    }.entries) {
      final file = File(entry.value);
      if (await file.exists()) {
        final loader = FontLoader(entry.key);
        loader.addFont(
          Future.value(ByteData.sublistView(await file.readAsBytes())),
        );
        await loader.load();
      }
    }
  });
  const audio = MethodChannel('com.cuso4.flashcards/audio');
  late AppDatabase db;
  late ProviderContainer container;
  late int deck;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audio, (_) async => null);
    db = AppDatabase(NativeDatabase.memory());
    deck = await DeckRepository(db).createDeck('操作系统 · 基础知识');
    final notes = NoteRepository(db);
    for (var i = 0; i < 2; i++) {
      await notes.createChoiceNote(
        deckId: deck,
        question: ChoiceQuestion(
          type: NoteType.singleChoice,
          prompt: '练习 ${i + 1}：以下关于进程与线程的说法，哪一项正确？',
          options: ['线程是进程中的执行单元', '线程之间无法共享资源', '进程不需要调度', '进程只能有一个线程'],
          correctIndexes: [0],
          explanation: '线程是操作系统进行运算调度的基本单位，同一进程中的线程共享该进程的资源。',
        ),
      );
    }
    await notes.createBasicNote(
      deckId: deck,
      front: '什么是进程',
      back: '程序的一次执行过程',
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
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('lunar-capture'),
        child: UncontrolledProviderScope(
          container: container,
          child: const Cuso4App(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/branding/app-logo.png'),
        tester.element(find.byType(Cuso4App)),
      ),
    );
    await tester.pumpAndSettle();
    addTearDown(() => tester.pumpWidget(const SizedBox()));
  }

  Future<void> go(WidgetTester tester, String path) async {
    container.read(appRouterProvider).go(path);
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> sheet(WidgetTester tester, int index) async {
    await tester.tap(find.byTooltip('本轮答题卡').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(ValueKey('answer-sheet-$index')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('answer-sheet-$index')));
    await tester.pumpAndSettle();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('lunar-capture')),
    );
    await tester.runAsync(() async {
      final screenshot = await boundary.toImage(pixelRatio: 2);
      try {
        final bytes = await screenshot.toByteData(
          format: ui.ImageByteFormat.png,
        );
        await Directory('build/previews').create(recursive: true);
        await File('build/previews/lunar-$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
      } finally {
        screenshot.dispose();
      }
    });
  }

  testWidgets(
    'answer sheet preserves submitted answers and links real practice records',
    (tester) async {
      await open(tester);
      await capture(tester, 'home-light');
      await go(tester, '/decks');
      await capture(tester, 'decks-light');
      await go(tester, '/settings');
      await capture(tester, 'settings-light');
      await go(tester, '/choice-practice/$deck');
      await tap(tester, '开始顺序练习');
      expect(find.byKey(const ValueKey('lunar-phase-signature')), findsNothing);
      expect(
        Theme.of(tester.element(find.byType(ChoicePracticeScaffold)))
            .colorScheme
            .primary,
        AppTheme.light.colorScheme.primary,
      );
      await tester.tap(find.byKey(const ValueKey('choice-option-1')));
      await tester.pumpAndSettle();
      await tap(tester, '提交答案');
      expect(find.text('回答错误'), findsOneWidget);
      await sheet(tester, 1);
      expect(find.text('第 2 / 2 张'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('choice-option-0')));
      await tester.pumpAndSettle();
      await sheet(tester, 0);
      expect(find.text('回答错误'), findsOneWidget);
      expect(
        tester
            .widget<ChoiceCardFace>(find.byType(ChoiceCardFace))
            .initialAttempt!
            .attempted,
        true,
      );
      await tap(tester, '下一张');
      expect(
        tester
            .widget<ChoiceCardFace>(find.byType(ChoiceCardFace))
            .initialAttempt!
            .selected,
        {0},
      );
      await tap(tester, '提交答案');
      await tap(tester, '完成本轮');
      expect(find.text('本轮练习完成'), findsOneWidget);
      await tap(tester, '查看本轮答题卡');
      await capture(tester, 'answer-sheet');
      await tester.tap(find.byKey(const ValueKey('answer-sheet-0')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tap(tester, '返回本轮结果');
      expect(find.text('答对 1 题 · 答错 1 题 · 未作答 0 题'), findsOneWidget);
      final events = await tester.runAsync(
        () async => (await db.select(db.appSettings).get())
            .where((s) => s.key.startsWith('practice:attempt:'))
            .toList(),
      );
      expect(events, hasLength(2));
      expect(
        (await tester.runAsync(() => db.select(db.wrongQuestions).get()))!
            .single
            .wrongCount,
        1,
      );
      expect(
        await tester.runAsync(() => db.select(db.reviewLogs).get()),
        isEmpty,
      );
      await go(tester, '/records?mode=practice');
      expect(find.text('正确率 50.0%'), findsOneWidget);
      await capture(tester, 'practice-records');
      final calendar = find.byKey(
        ValueKey(
          'calendar-${DateTime.now().year}-${DateTime.now().month}-${DateTime.now().day}',
        ),
      );
      await tester.ensureVisible(calendar);
      await tester.tap(calendar);
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: find.byType(ListTile), matching: find.text('答对')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: find.byType(ListTile), matching: find.text('答错')),
        findsOneWidget,
      );
      await capture(tester, 'practice-day');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'exterior and answer sheet support dark, large text and landscape',
    (tester) async {
      await open(tester);
      await tester.runAsync(
        () async => db
            .into(db.appSettings)
            .insertOnConflictUpdate(
              AppSettingsCompanion.insert(key: 'theme', valueJson: 'dark'),
            ),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'home-dark');
      await tester.runAsync(
        () => FontSettingsRepository(db).save(FontSettings(uiPercent: 150)),
      );
      await tester.pumpAndSettle();
      await capture(tester, 'home-large');
      await go(tester, '/settings');
      await capture(tester, 'settings-large');
      await go(tester, '/records?mode=practice');
      await capture(tester, 'records-large');
      await go(tester, '/choice-practice/$deck');
      await tap(tester, '开始顺序练习');
      tester.view.physicalSize = const Size(1920, 960);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('本轮答题卡'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('answer-sheet-1')));
      await tester.pumpAndSettle();
      await capture(tester, 'sheet-landscape-large');
      await tester.tap(find.byKey(const ValueKey('answer-sheet-1')));
      await tester.pumpAndSettle();
      expect(find.text('第 2 / 2 张'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
