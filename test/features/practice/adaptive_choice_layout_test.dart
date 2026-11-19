import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/app/router/app_router.dart';
import 'package:cuso4_flashcards/core/content/card_content.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/media/media_repository.dart';
import 'package:cuso4_flashcards/core/widgets/pressable_action.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/domain/choice_question.dart';
import 'package:cuso4_flashcards/features/decks/domain/note.dart';
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
    // Host fonts are only for readable local layout previews, never APK assets.
    for (final entry in {
      'Roboto': 'C:/Windows/Fonts/msyh.ttc',
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
  const channel = MethodChannel('com.cuso4.flashcards/audio');
  late AppDatabase db;
  late int deck;
  ProviderContainer? container;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    db = AppDatabase(NativeDatabase.memory());
    deck = await DeckRepository(db).createDeck('计算机基础 · 练习章节');
  });
  tearDown(() async {
    container?.dispose();
    container = null;
    await db.close();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  Future<void> open(
    WidgetTester tester,
    ChoiceQuestion question, {
    FontSettings? fonts,
    MediaRepository? media,
  }) async {
    await tester.runAsync(() async {
      if (fonts != null) await FontSettingsRepository(db).save(fonts);
      await NoteRepository(
        db,
        mediaRepository: media,
      ).createChoiceNote(deckId: deck, question: question);
    });
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        if (media != null) mediaRepositoryProvider.overrideWithValue(media),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container!, child: const Cuso4App()),
    );
    await tester.pumpAndSettle();
    container!.read(appRouterProvider).go('/choice-practice/$deck');
    await tester.pumpAndSettle();
    if (media == null) {
      await tap(tester, '开始顺序练习');
    } else {
      await tester.ensureVisible(find.text('开始顺序练习'));
      await tester.tap(find.text('开始顺序练习'));
      await tester.pump();
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  double bodySize(WidgetTester tester, String source) {
    final content = find.byWidgetPredicate(
      (w) => w is CardContent && w.source == source,
    );
    final rich = find
        .descendant(of: content, matching: find.byType(RichText))
        .first;
    final widget = tester.widget<RichText>(rich);
    return widget.textScaler.scale(widget.text.style!.fontSize!);
  }

  testWidgets(
    'ordinary four-option question and actions fit phone without scrolling',
    (tester) async {
      final previousShadows = debugDisableShadows;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = previousShadows);
      await open(
        tester,
        ChoiceQuestion(
          type: NoteType.singleChoice,
          prompt: '操作系统负责管理计算机硬件与软件资源。下列关于进程和线程的说法，哪一项是正确的？',
          options: [
            '线程是进程中的执行单元，同一进程内的线程可以共享部分资源。',
            '不同进程中的线程总是能够直接共享全部内存空间。',
            '进程与线程的调度完全不需要操作系统参与。',
            '一个进程在任何情况下都只能包含一个线程。',
          ],
          correctIndexes: [0],
        ),
      );
      expect(
        find.byKey(const ValueKey('adaptive-choice-viewport')),
        findsOneWidget,
      );
      for (var i = 0; i < 4; i++) {
        final option = find.byKey(ValueKey('choice-option-$i'));
        expect(option.hitTestable(), findsOneWidget);
        expect(tester.getSize(option).height, greaterThanOrEqualTo(48));
      }
      expect(find.text('提交答案').hitTestable(), findsOneWidget);
      expect(find.text('查看解析').hitTestable(), findsOneWidget);
      final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('adaptive-choice-scroll')),
      );
      expect(scroll.controller!.position.maxScrollExtent, lessThanOrEqualTo(1));
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      await tester.runAsync(() async {
        final screenshot = await boundary.toImage(pixelRatio: 3);
        try {
          final bytes = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await Directory('build/previews').create(recursive: true);
          await File('build/previews/adaptive-choice-phone.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          screenshot.dispose();
        }
      });
      await tester.tap(find.byKey(const ValueKey('choice-option-0')));
      await tester.pumpAndSettle();
      await tap(tester, '提交答案');
      expect(find.text('题目解析'), findsOneWidget);
      await tap(tester, '返回题目');
      expect(find.text('完成本轮').hitTestable(), findsOneWidget);
      expect(find.text('回答正确'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugDisableShadows = previousShadows;
      await close(tester);
    },
  );

  testWidgets(
    'long question clamps temporary font, preserves settings and scrolls complete content',
    (tester) async {
      final prompt = List.filled(
        45,
        '这是一段必须完整保留的长题干，包含重要条件，不能因为屏幕大小而被截断。',
      ).join();
      await open(
        tester,
        ChoiceQuestion(
          type: NoteType.multipleChoice,
          prompt: prompt,
          options: List.generate(
            8,
            (i) => '选项$i：${List.filled(5, '长选项内容必须完整显示。').join()}',
          ),
          correctIndexes: [0, 1],
        ),
        fonts: FontSettings(uiPercent: 100, cardPercent: 125),
      );
      expect(
        find.byKey(const ValueKey('adaptive-choice-viewport')),
        findsOneWidget,
      );
      final effective = bodySize(tester, prompt);
      expect(effective, greaterThanOrEqualTo(16));
      expect(effective, greaterThanOrEqualTo(22 * 1.25 * .75 - .01));
      expect(effective, lessThan(22 * 1.25));
      final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('adaptive-choice-scroll')),
      );
      expect(scroll.controller!.position.maxScrollExtent, greaterThan(0));
      expect(find.text('查看解析').hitTestable(), findsOneWidget);
      expect(find.text('提交答案').hitTestable(), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('choice-option-7')));
      expect(
        find.byKey(const ValueKey('choice-option-7')).hitTestable(),
        findsOneWidget,
      );
      final stored = (await tester.runAsync(
        () => db
            .customSelect(
              "SELECT value_json FROM app_settings WHERE key='fontSettings'",
            )
            .getSingle(),
      ))!;
      expect(
        FontSettings.decode(stored.read<String>('value_json')).cardPercent,
        125,
      );
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets(
    'temporary reduction fits a medium question and reflows on rotation',
    (tester) async {
      final prompt = List.filled(4, '进程和线程拥有不同的资源管理方式，请结合条件判断下列说法。').join();
      await open(
        tester,
        ChoiceQuestion(
          type: NoteType.singleChoice,
          prompt: prompt,
          options: List.generate(4, (i) => '选项$i：进程与线程的执行方式受到资源分配和调度机制的共同影响。'),
          correctIndexes: [0],
        ),
        fonts: FontSettings(cardPercent: 125),
      );
      final scroll = tester.widget<SingleChildScrollView>(
        find.byKey(const ValueKey('adaptive-choice-scroll')),
      );
      expect(scroll.controller!.position.maxScrollExtent, lessThanOrEqualTo(1));
      expect(bodySize(tester, prompt), lessThan(27.5));
      expect(bodySize(tester, prompt), greaterThanOrEqualTo(27.5 * .75 - .01));
      tester.view.physicalSize = const Size(2712, 1220);
      await tester.pumpAndSettle();
      expect(find.text('查看解析').hitTestable(), findsOneWidget);
      expect(find.text('提交答案').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  for (final path in ['/favorites', '/wrong-questions']) {
    testWidgets(
      '$path direct choice preview uses adaptive layout and never records mistakes',
      (tester) async {
        await open(
          tester,
          ChoiceQuestion(
            type: NoteType.singleChoice,
            prompt: '预览选择题',
            options: ['正确选项', '错误选项'],
            correctIndexes: [0],
          ),
        );
        final id = (await tester.runAsync(() => db.select(db.cards).get()))!
            .single
            .id;
        container!.read(appRouterProvider).go('$path/$id');
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('adaptive-choice-viewport')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('choice-option-1')));
        await tester.pumpAndSettle();
        await tap(tester, '提交答案');
        expect(find.text('回答错误'), findsOneWidget);
        expect(find.text('完成本轮'), findsNothing);
        await tap(tester, '返回题目');
        expect(find.text('重新作答').hitTestable(), findsOneWidget);
        expect(
          (await tester.runAsync(() => db.select(db.wrongQuestions).get()))!,
          isEmpty,
        );
        await tap(tester, '重新作答');
        expect(find.text('回答错误'), findsNothing);
        expect(tester.takeException(), isNull);
        await close(tester);
      },
    );
  }

  testWidgets(
    'adaptive images open full viewer and return without selecting the option',
    (tester) async {
      final root = await tester.runAsync(
        () async =>
            (await Directory('build/test-temp').create(recursive: true))
                .createTemp('adaptive-image-'),
      );
      late String hash;
      late MediaRepository media;
      await tester.runAsync(() async {
        final bytes = await File('assets/branding/app-logo.png').readAsBytes();
        hash = sha256.convert(bytes).toString();
        await File('${root!.path}/$hash').writeAsBytes(bytes);
        await db
            .into(db.media)
            .insert(
              MediaCompanion.insert(
                contentHash: hash,
                originalName: 'fixture.png',
                relativePath: hash,
                mimeType: 'image/png',
                byteLength: bytes.length,
                createdAtUtc: 0,
              ),
            );
        media = MediaRepository(db, directory: root);
      });
      await open(
        tester,
        ChoiceQuestion(
          type: NoteType.singleChoice,
          prompt: '请选择与图示对应的选项。',
          options: ['<img src="media:$hash">', '文字选项'],
          correctIndexes: [0],
        ),
        media: media,
      );
      await tester.runAsync(() async {
        for (var i = 0; i < 100; i++) {
          await tester.pump();
          if (tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((w) => w.image != null)) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('Image failed to decode');
      });
      await tester.pumpAndSettle();
      final zoom = find.byTooltip('放大图片');
      expect(zoom.hitTestable(), findsOneWidget);
      await tester.tap(zoom);
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsOneWidget);
      await tester.tap(find.byTooltip('关闭图片'));
      await tester.pumpAndSettle();
      expect(find.text('提交答案').hitTestable(), findsOneWidget);
      final submit = find.ancestor(
        of: find.text('提交答案'),
        matching: find.byType(PressableAction),
      );
      expect(tester.widget<PressableAction>(submit).onPressed, isNull);
      expect(
        (await tester.runAsync(() => db.select(db.wrongQuestions).get()))!,
        isEmpty,
      );
      expect(tester.takeException(), isNull);
      await close(tester);
      await tester.runAsync(() => root!.delete(recursive: true));
    },
  );
}
