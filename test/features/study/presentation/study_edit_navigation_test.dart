import 'dart:io';

import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/app/router/app_router.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/media/media_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/decks/presentation/note_editor_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late int deck;
  late NoteRepository notes;
  late int noteId;
  late Directory root;
  late ProviderContainer container;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    deck = await DeckRepository(db).createDeck('编辑验收');
    notes = NoteRepository(db);
    noteId = await notes.createBasicNote(
      deckId: deck,
      front: '原问题',
      back: '原答案',
    );
    await notes.createClozeNote(
      deckId: deck,
      text: '颜色 {{c1::蓝色}}，形状 {{c2::方形}}',
    );
    final parent = await Directory('build/test_media').create(recursive: true);
    root = await parent.createTemp('study-edit-');
    container = ProviderContainer(
      overrides: [
        databaseProvider.overrideWithValue(db),
        mediaRepositoryProvider.overrideWithValue(
          MediaRepository(db, directory: root),
        ),
      ],
    );
  });
  tearDown(() async {
    container.dispose();
    await db.close();
    await root.delete(recursive: true);
  });
  testWidgets('study edit displays original fields and returns to same card', (
    tester,
  ) async {
    final router = container.read(appRouterProvider);
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/study?deckId=$deck');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('编辑卡片'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(NoteEditorPage), findsOneWidget);
    final front = find.byKey(const ValueKey('note-front'));
    expect(front, findsOneWidget);
    expect(tester.widget<TextField>(front).controller!.text, '原问题');
    await tester.enterText(front, '改正后的问题');
    final save = find.text('保存卡片');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect((await notes.getNote(noteId)).fields['front'], '改正后的问题');
    expect(find.text('改正后的问题'), findsOneWidget);
    expect(await db.select(db.reviewLogs).get(), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'recitation shows answers, resumes position and leaves review data unchanged',
    (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('com.cuso4.flashcards/audio'),
        (_) async => null,
      );
      final before = await db.select(db.cards).get();
      final router = container.read(appRouterProvider);
      router.go('/recitation/$deck');
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('背卡模式'), findsOneWidget);
      expect(find.text('原答案'), findsOneWidget);
      expect(find.text('第 1 / 2 条'), findsOneWidget);
      await tester.ensureVisible(find.text('下一条'));
      await tester.tap(find.text('下一条'));
      await tester.pumpAndSettle();
      expect(find.textContaining('蓝色'), findsWidgets);
      expect(find.text('第 2 / 2 条'), findsOneWidget);
      expect(await db.select(db.cards).get(), before);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      router.go('/decks/$deck');
      await tester.pumpAndSettle();
      router.push('/recitation/$deck');
      await tester.pumpAndSettle();
      expect(find.text('第 2 / 2 条'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
