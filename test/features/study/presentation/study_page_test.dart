import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/feedback/feedback_controller.dart';
import 'package:cuso4_flashcards/features/decks/data/deck_repository.dart';
import 'package:cuso4_flashcards/features/decks/data/note_repository.dart';
import 'package:cuso4_flashcards/features/study/data/study_repository.dart';
import 'package:cuso4_flashcards/features/study/presentation/study_page.dart';
import 'package:cuso4_flashcards/features/settings/data/study_settings_repository.dart';
import 'package:cuso4_flashcards/features/settings/domain/study_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingFeedback implements FeedbackPlatform {
  final events = <FeedbackKind>[];
  @override
  Future<void> perform(FeedbackKind kind) async => events.add(kind);
}

void main() {
  late AppDatabase db;
  late int deck;
  late RecordingFeedback feedback;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    deck = await DeckRepository(db).createDeck('化学');
    await NoteRepository(db).createBasicNote(
      deckId: deck,
      front: 'CuSO<sub>4</sub> 是什么？',
      back: '硫酸铜',
    );
    await NoteRepository(db)
        .createClozeNote(deckId: deck, text: '晶体是 {{c1::蓝色}}');
    feedback = RecordingFeedback();
  });
  tearDown(() async => db.close());

  Future<void> open(WidgetTester tester, {double scale = 1}) async {
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          studyRepositoryProvider.overrideWithValue(StudyRepository(db)),
        ],
        child: FeedbackScope(
          controller: FeedbackController(platform: feedback),
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: StudyPage(deckId: deck),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('answer gating, one rating, tactile confirmation and undo', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('硫酸铜'), findsNothing);
    expect(find.byKey(const ValueKey('rating-good')), findsNothing);
    await tester.tap(find.text('显示答案'));
    await tester.pumpAndSettle();
    expect(find.text('硫酸铜'), findsOneWidget);
    for (final name in ['again', 'hard', 'good', 'easy']) {
      expect(find.byKey(ValueKey('rating-$name')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('rating-good')));
    await tester.tap(find.byKey(const ValueKey('rating-good')));
    await tester.pumpAndSettle();
    expect((await db.select(db.reviewLogs).get()).length, 1);
    expect(
      feedback.events.where((e) => e == FeedbackKind.mediumImpact).length,
      1,
    );
    await tester.tap(find.byTooltip('撤销上次评分'));
    await tester.pumpAndSettle();
    expect(await db.select(db.reviewLogs).get(), isEmpty);
    expect(find.text('显示答案'), findsOneWidget);
    await tester.tap(find.byTooltip('收藏卡片'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('取消收藏'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'study entry reads persisted limits before showing any new card',
    (tester) async {
      await StudySettingsRepository(db).save(StudySettings(dailyNewLimit: 0));
      await open(tester);
      expect(find.text('当前没有可学习卡片'), findsOneWidget);
      expect(find.text('显示答案'), findsNothing);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'large text keeps answer and ratings accessible on the target phone',
    (tester) async {
      await open(tester, scale: 1.8);
      await tester.ensureVisible(find.text('显示答案'));
      await tester.tap(find.text('显示答案'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(2712, 1220);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.byKey(const ValueKey('rating-easy')));
      await tester.tap(find.byKey(const ValueKey('rating-easy')));
      await tester.pumpAndSettle();
      expect((await db.select(db.reviewLogs).get()).length, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
