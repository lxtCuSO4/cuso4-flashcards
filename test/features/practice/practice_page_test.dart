import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/app/router/app_router.dart';
import 'package:cuso4_flashcards/core/content/card_content.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/media/media_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/practice/data/practice_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ControlledPracticeRepository extends PracticeRepository {
  ControlledPracticeRepository(super.db, this.ids);
  final List<int> ids;
  Completer<void>? gate;
  int calls = 0;
  bool fail = false;
  @override
  Future<PracticeRound> sample({
    int? deckId,
    required bool includeChildren,
    required int count,
    bool favoritesOnly = false,
  }) async {
    calls++;
    if (gate != null) await gate!.future;
    if (fail) throw StateError('抽卡暂时失败，请重试');
    return PracticeRound(deckName: '操作系统', cardIds: ids.take(count));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const audioChannel = MethodChannel('com.cuso4.flashcards/audio');
  late AppDatabase db;
  late int deck;
  late List<int> ids;
  ProviderContainer? container;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, (_) async => null);
    db = AppDatabase(NativeDatabase.memory());
    deck = await DeckRepository(db).createDeck('操作系统');
    final notes = NoteRepository(db);
    await notes.createBasicNote(deckId: deck, front: '什么是进程？', back: '运行中的程序');
    await notes.createClozeNote(
      deckId: deck,
      text: '线程属于{{c1::进程}}',
      extra: '填空补充',
    );
    ids = (await db.select(db.cards).get()).map((c) => c.id).toList();
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioChannel, null);
    container?.dispose();
    container = null;
    await db.close();
  });

  Future<void> open(
    WidgetTester tester, {
    PracticeRepository? repository,
    MediaRepository? media,
  }) async {
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        if (repository != null)
          practiceRepositoryProvider.overrideWithValue(repository),
        if (media != null) mediaRepositoryProvider.overrideWithValue(media),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(container: container!, child: const Cuso4App()),
    );
    await tester.pumpAndSettle();
    container!.read(appRouterProvider).go('/decks/$deck');
    await tester.pumpAndSettle();
    await tester.tap(find.text('随机练习'));
    await tester.pumpAndSettle();
    expect(find.text('开始随机练习'), findsOneWidget);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    container?.dispose();
    container = null;
    await tester.pumpAndSettle();
  }

  Future<List<Object?>> snapshot() async => [
    for (final table in [
      'cards',
      'notes',
      'decks',
      'favorites',
      'review_logs',
      'app_settings',
    ])
      (await db.customSelect('SELECT * FROM $table').get())
          .map((r) => r.data)
          .toList(),
  ];

  testWidgets(
    'entry, answer gating, unique full round and repeat never write learning data',
    (tester) async {
      await open(tester);
      final before = await tester.runAsync(snapshot);
      expect(
        tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isTrue,
      );
      await tap(tester, '开始随机练习');
      final seen = <int>{};
      for (var i = 0; i < 2; i++) {
        expect(find.text('第 ${i + 1} / 2 张'), findsOneWidget);
        expect(find.text('答案'), findsNothing);
        final face = find.byWidgetPredicate(
          (w) =>
              w.key == ValueKey('practice-card-${ids[0]}') ||
              w.key == ValueKey('practice-card-${ids[1]}'),
        );
        expect(face, findsOneWidget);
        final key = tester.widget(face).key as ValueKey<String>;
        expect(seen.add(int.parse(key.value.split('-').last)), isTrue);
        expect(find.byType(CardContent), findsOneWidget);
        final question = tester
            .widget<CardContent>(find.byType(CardContent))
            .source;
        expect(question, anyOf('什么是进程？', '线程属于[…]'));
        expect(find.text('填空补充', findRichText: true), findsNothing);
        await tap(tester, '显示答案');
        expect(find.text('答案'), findsOneWidget);
        expect(
          tester
              .widgetList<CardContent>(find.byType(CardContent))
              .map((w) => w.source),
          question == '什么是进程？'
              ? ['什么是进程？', '运行中的程序']
              : ['线程属于[…]', '线程属于进程', '填空补充'],
        );
        expect(find.text('良好'), findsNothing);
        final next = find.text(i == 1 ? '完成本轮' : '下一张');
        await tester.ensureVisible(next);
        await tester.tap(next);
        await tester.tap(next);
        await tester.pumpAndSettle();
      }
      expect(find.text('本轮练习完成'), findsOneWidget);
      expect(find.text('已练习 2 张'), findsOneWidget);
      await tap(tester, '再练一轮');
      expect(find.text('第 1 / 2 张'), findsOneWidget);
      expect(find.text('答案'), findsNothing);
      expect(await tester.runAsync(snapshot), before);
      await close(tester);
    },
  );

  testWidgets('count validation, empty scope and include chapters are usable', (
    tester,
  ) async {
    final child = await tester.runAsync(
      () => DeckRepository(db).createDeck('只有子章节', parentId: deck),
    );
    await tester.runAsync(() async {
      for (final note in await db.select(db.notes).get()) {
        await NoteRepository(db).deleteNote(note.id);
      }
      await NoteRepository(db).createBasicNote(deckId: child!, front: '子章节问题');
    });
    await open(tester);
    for (final input in ['0', '501', '']) {
      await tester.enterText(find.byType(TextFormField), input);
      await tap(tester, '开始随机练习');
      expect(find.text('请输入 1–500 之间的整数'), findsOneWidget);
    }
    await tester.enterText(find.byType(TextFormField), '20');
    await tester.tap(find.byType(SwitchListTile));
    await tap(tester, '开始随机练习');
    expect(find.text('当前范围没有卡片。可包含子章节，或先添加、导入卡片。'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tap(tester, '开始随机练习');
    expect(find.text('第 1 / 1 张'), findsOneWidget);
    expect(find.text('子章节问题'), findsOneWidget);
    await close(tester);
  });

  testWidgets(
    'practice displays an actual local image through the existing renderer',
    (tester) async {
      final root = await tester.runAsync(() async {
        final parent = await Directory('build/test-temp')
            .create(recursive: true);
        return parent.createTemp('practice-image-');
      });
      final hash = 'a' * 64;
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
        const Rect.fromLTWH(0, 0, 2, 2),
        Paint()..color = Colors.green,
      );
      final picture = recorder.endRecording();
      final image = await tester.runAsync(() => picture.toImage(2, 2));
      final bytes = await tester.runAsync(
        () => image!.toByteData(format: ui.ImageByteFormat.png),
      );
      image!.dispose();
      picture.dispose();
      await tester.runAsync(() async {
        await File('${root!.path}/$hash')
            .writeAsBytes(bytes!.buffer.asUint8List());
        await db
            .into(db.media)
            .insert(
              MediaCompanion.insert(
                contentHash: hash,
                originalName: 'diagram.png',
                relativePath: hash,
                mimeType: 'image/png',
                byteLength: bytes.lengthInBytes,
                createdAtUtc: 0,
              ),
            );
        await NoteRepository(db).createBasicNote(
          deckId: deck,
          front: '<img src="media:$hash">',
          back: '示意图答案',
        );
      });
      final imageId = (await tester.runAsync(() => db.select(db.cards).get()))!
          .last
          .id;
      await open(
        tester,
        repository: ControlledPracticeRepository(db, [imageId]),
        media: MediaRepository(db, directory: root),
      );
      // Filesystem resolution and image decoding need real async I/O; wait
      // for the decoded image rather than spinning its loading animation.
      await tester.tap(find.text('开始随机练习'));
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 100; attempt++) {
          await tester.pump();
          final images = tester.widgetList<RawImage>(find.byType(RawImage));
          if (images.any((image) => image.image != null)) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        fail('Local image did not decode');
      });
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(find.text('图片缺失或无法显示'), findsNothing);
      await tap(tester, '显示答案');
      expect(find.text('示意图答案', findRichText: true), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
      await tester.runAsync(() => root!.delete(recursive: true));
    },
  );

  testWidgets(
    'loading is locked, errors retry, and deleted cards can be skipped',
    (tester) async {
      final repository = ControlledPracticeRepository(db, ids)
        ..gate = Completer<void>();
      await open(tester, repository: repository);
      await tester.tap(find.text('开始随机练习'));
      await tester.pump();
      await tester.tap(find.text('开始随机练习'));
      expect(repository.calls, 1);
      repository.fail = true;
      repository.gate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('抽卡暂时失败，请重试'), findsOneWidget);
      repository.fail = false;
      repository.gate = null;
      await tap(tester, '开始随机练习');
      await tester.runAsync(() async {
        final card = await (db.select(
          db.cards,
        )..where((c) => c.id.equals(ids.last))).getSingle();
        await NoteRepository(db).deleteNote(card.noteId);
      });
      await tap(tester, '显示答案');
      await tap(tester, '下一张');
      expect(find.text('卡片已删除或暂时无法加载。可以重试，或跳过这张卡片。'), findsOneWidget);
      await tap(tester, '重试加载');
      expect(find.text('跳过此卡'), findsOneWidget);
      await tap(tester, '跳过此卡');
      expect(find.text('已练习 1 张'), findsOneWidget);
      expect(find.text('另有 1 张未能加载，已跳过'), findsOneWidget);
      await close(tester);
    },
  );

  testWidgets(
    'dark mode, large text, small phone and landscape retain actions',
    (tester) async {
      await db
          .into(db.appSettings)
          .insert(AppSettingsCompanion.insert(key: 'theme', valueJson: 'dark'));
      await open(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      tester.view.physicalSize = const Size(1125, 2001);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(TextFormField))).brightness,
        Brightness.dark,
      );
      await tap(tester, '开始随机练习');
      tester.view.physicalSize = const Size(2001, 1125);
      await tester.pumpAndSettle();
      await tap(tester, '显示答案');
      await tap(tester, '下一张');
      expect(find.text('第 2 / 2 张'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );
}
