import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late int root;
  late int chapter;
  late int other;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final decks = DeckRepository(db);
    root = await decks.createDeck('操作系统');
    chapter = await decks.createDeck('第一章', parentId: root);
    final section = await decks.createDeck('第一节', parentId: chapter);
    await decks.createDeck('第二章', parentId: root);
    other = await decks.createDeck('数据库');
    await decks.createDeck('关系模型', parentId: other);
    await NoteRepository(db)
        .createBasicNote(deckId: section, front: '进程是什么？', back: '运行中的程序');
  });
  tearDown(() async => db.close());

  Future<void> open(WidgetTester tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: const Cuso4App(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组').last);
    await tester.pumpAndSettle();
  }

  testWidgets('all chapter groups start collapsed', (tester) async {
    await open(tester);
    expect(find.text('操作系统'), findsOneWidget);
    expect(find.text('第一章'), findsNothing);
    expect(find.text('第一节'), findsNothing);
    expect(find.text('关系模型'), findsNothing);
    expect(find.byTooltip('展开操作系统'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('nested arrows preserve child choices when the parent closes', (
    tester,
  ) async {
    await open(tester);
    final before = await tester.runAsync(
      () async => (await db.select(db.cards).get()).single.toJson(),
    );
    await tester.tap(find.byTooltip('展开操作系统'));
    await tester.pumpAndSettle();
    expect(find.text('第一章'), findsOneWidget);
    expect(find.text('第一节'), findsNothing);
    expect(find.byTooltip('展开第二章'), findsNothing);
    await tester.tap(find.byTooltip('展开第一章'));
    await tester.pumpAndSettle();
    expect(find.text('第一节'), findsOneWidget);
    await tester.tap(find.byTooltip('收起操作系统'));
    await tester.pumpAndSettle();
    expect(find.text('第一节'), findsNothing);
    await tester.tap(find.byTooltip('展开操作系统'));
    await tester.pumpAndSettle();
    expect(find.text('第一节'), findsOneWidget);
    await tester.runAsync(() async {
      expect((await db.select(db.cards).get()).single.toJson(), before);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
    });
    final settings = (await tester.runAsync(
      () => db.select(db.appSettings).get(),
    ))!;
    expect(
      settings.singleWhere((s) => s.key == 'deckExpanded.$root').valueJson,
      'true',
    );
    expect(
      settings.singleWhere((s) => s.key == 'deckExpanded.$chapter').valueJson,
      'true',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('independent deck choices survive a fresh app widget', (
    tester,
  ) async {
    await open(tester);
    await tester.tap(find.byTooltip('展开操作系统'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('展开数据库'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('收起操作系统'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await open(tester);
    expect(find.text('第一章'), findsNothing);
    expect(find.text('关系模型'), findsOneWidget);
    expect(
      (await tester.runAsync(() => db.select(db.appSettings).get()))!
          .singleWhere((s) => s.key == 'deckExpanded.$other')
          .valueJson,
      'true',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets('double tapping an arrow does not submit conflicting saves', (
    tester,
  ) async {
    await open(tester);
    final arrow = find.byTooltip('展开操作系统');
    await tester.tap(arrow);
    await tester.tap(arrow);
    await tester.pumpAndSettle();
    expect(find.text('第一章'), findsOneWidget);
    expect(
      (await tester.runAsync(() => db.select(db.appSettings).get()))!
          .singleWhere((s) => s.key == 'deckExpanded.$root')
          .valueJson,
      'true',
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'failed preference writes keep chapters closed and show recovery feedback',
    (tester) async {
      await db.customStatement(
        "CREATE TRIGGER fail_expansion BEFORE INSERT ON app_settings WHEN NEW.key LIKE 'deckExpanded.%' BEGIN SELECT RAISE(FAIL, 'preference failure'); END",
      );
      await open(tester);
      await tester.tap(find.byTooltip('展开操作系统'));
      await tester.pumpAndSettle();
      expect(find.text('第一章'), findsNothing);
      expect(find.text('操作未完成，请重试。'), findsOneWidget);
      expect(find.byTooltip('展开操作系统'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'name still opens the deck; arrows fit large text and landscape',
    (tester) async {
      await open(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.tap(find.byTooltip('展开操作系统'));
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byKey(ValueKey('deck-toggle-$root'))).width,
        greaterThanOrEqualTo(48),
      );
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(2712, 1220);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('操作系统'));
      await tester.pumpAndSettle();
      expect(find.text('学习这个牌组'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
