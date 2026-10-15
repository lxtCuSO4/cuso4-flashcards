import 'dart:io';

import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/core/content/card_content.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/media/media_repository.dart';
import 'package:cuso4_flashcards/core/media/prepared_image.dart';
import 'package:cuso4_flashcards/features/decks/application/editor_image_picker.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/presentation/note_editor_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../../support/image_fixture.dart';

void main() {
  late AppDatabase db;
  late int deck;
  late GoRouter router;
  late Directory mediaRoot;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    deck = await DeckRepository(db).createDeck('化学');
    final parent = await Directory('build/test_media').create(recursive: true);
    mediaRoot = await parent.createTemp('editor-widget-');
    const channel = MethodChannel('com.cuso4.flashcards/audio');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
  });
  tearDown(() async {
    router.dispose();
    await db.close();
    await mediaRoot.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.cuso4.flashcards/audio'),
          null,
        );
  });

  Future<void> open(
    WidgetTester tester, {
    PreparedImage? image,
    Future<PreparedImage?> Function()? picker,
    bool dark = false,
  }) async {
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('返回牌组')),
          routes: [
            GoRoute(
              path: 'edit',
              builder: (_, _) => NoteEditorPage(deckId: deck),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          mediaRepositoryProvider.overrideWithValue(
            MediaRepository(db, directory: mediaRoot),
          ),
          editorImagePickerProvider.overrideWithValue(
            picker ?? () async => image,
          ),
          settingsProvider.overrideWith(
            (ref) => Stream.value({'theme': dark ? 'dark' : 'light'}),
          ),
        ],
        child: MaterialApp.router(
          routerConfig: router,
          theme: dark
              ? ThemeData.dark(useMaterial3: true)
              : ThemeData(useMaterial3: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.8),
              disableAnimations: true,
            ),
            child: child!,
          ),
        ),
      ),
    );
    router.push('/edit');
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'inserts at selection, previews draft image without writes, discard is guarded',
    (tester) async {
      final image = await tester.runAsync(
        () async =>
            PreparedImage.fromBytes(await imageBytes(), name: 'test.png'),
      );
      await open(tester, image: image);
      final front = find.byKey(const ValueKey('note-front'));
      await tester.enterText(front, '蓝色晶体');
      final field = tester.widget<TextField>(front);
      field.controller!.selection = const TextSelection.collapsed(offset: 2);
      await tap(tester, '正面插入图片');
      expect(
        field.controller!.text,
        contains('蓝色\n<img src="${image!.token}">\n晶体'),
      );
      await tap(tester, '预览卡片');
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump();
          if (tester
              .widgetList<RawImage>(find.byType(RawImage))
              .any((item) => item.image != null)) {
            return;
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('Draft image did not decode');
      });
      await tester.pump();
      expect(
        tester
            .widgetList<CardContent>(find.byType(CardContent))
            .first
            .draftImages[image.token],
        isNotNull,
      );
      expect(find.byType(Image), findsOneWidget);
      await tester.runAsync(() async {
        expect(await db.select(db.notes).get(), isEmpty);
        expect(await db.select(db.media).get(), isEmpty);
        expect(await db.select(db.reviewLogs).get(), isEmpty);
      });
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('放弃修改？'), findsOneWidget);
      await tap(tester, '放弃修改');
      expect(find.text('返回牌组'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'picker cancellation and failure retain text; save commits inserted image',
    (tester) async {
      final image = (await tester.runAsync(
        () async =>
            PreparedImage.fromBytes(await imageBytes(), name: 'image.png'),
      ))!;
      var calls = 0;
      await open(
        tester,
        picker: () async {
          calls++;
          if (calls == 1) return null;
          if (calls == 2) throw ArgumentError('图片损坏，请重选');
          return image;
        },
      );
      final front = find.byKey(const ValueKey('note-front'));
      await tester.enterText(front, '保留文字');
      await tap(tester, '正面插入图片');
      expect(tester.widget<TextField>(front).controller!.text, '保留文字');
      await tap(tester, '正面插入图片');
      expect(find.text('图片损坏，请重选'), findsOneWidget);
      expect(tester.widget<TextField>(front).controller!.text, '保留文字');
      ScaffoldMessenger.of(tester.element(front)).removeCurrentSnackBar();
      await tester.pumpAndSettle();
      await tap(tester, '正面插入图片');
      await tester.ensureVisible(find.text('保存卡片'));
      await tester.tap(find.text('保存卡片'));
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump();
          if (find.text('返回牌组').evaluate().isNotEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('Save did not complete');
      });
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        final note = (await db.select(db.notes).get()).single;
        expect(note.fieldsJson, contains(image.token));
        expect((await db.select(db.media).get()).single.referenceCount, 1);
        final media = MediaRepository(db, directory: mediaRoot);
        expect(
          await media.resolve(image.token, kind: MediaKind.image),
          isNotNull,
        );
        expect(await db.select(db.reviewLogs).get(), isEmpty);
      });
      expect(find.text('返回牌组'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'cloze preview selects each index and resets answer without writes in dark mode',
    (tester) async {
      await open(tester, dark: true);
      await tap(tester, '填空卡');
      await tester.enterText(
        find.byKey(const ValueKey('note-front')),
        '{{c1::蓝色::颜色}} 和 {{c2::结晶水}}',
      );
      await tap(tester, '预览卡片');
      expect(find.textContaining('[颜色]', findRichText: true), findsOneWidget);
      await tap(tester, '显示答案');
      expect(
        find.textContaining('蓝色 和 结晶水', findRichText: true),
        findsOneWidget,
      );
      await tap(tester, '填空 2');
      expect(
        find.textContaining('蓝色 和 […]', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('显示答案'), findsOneWidget);
      tester.view.physicalSize = const Size(1125, 2436);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(2436, 1125);
      await tester.pumpAndSettle();
      await tap(tester, '显示答案');
      await tester.runAsync(() async {
        expect(await db.select(db.notes).get(), isEmpty);
        expect(await db.select(db.cards).get(), isEmpty);
        expect(await db.select(db.reviewLogs).get(), isEmpty);
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
