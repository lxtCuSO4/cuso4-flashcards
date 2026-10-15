import 'dart:async';

import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/settings/data/study_settings_repository.dart';
import 'package:cuso4_flashcards/features/settings/domain/study_settings.dart';
import 'package:cuso4_flashcards/features/settings/presentation/study_settings_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ControlledSettingsRepository extends StudySettingsRepository {
  ControlledSettingsRepository(super.db);
  bool fail = false;
  Completer<void>? saving;
  int saves = 0;
  @override
  Future<void> save(StudySettings settings) async {
    saves++;
    await saving?.future;
    if (fail) throw StateError('failure');
    await super.save(settings);
  }
}

void main() {
  late AppDatabase db;
  late ControlledSettingsRepository repository;
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = ControlledSettingsRepository(db);
  });
  tearDown(() => db.close());

  Finder field(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(TextFormField));
  Future<void> change(WidgetTester tester, String label, String text) async {
    await tester.ensureVisible(field(label));
    await tester.enterText(field(label), text);
    await tester.pumpAndSettle();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.text('保存学习设置');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(() async {
      if (repository.saving?.isCompleted == false) {
        repository.saving!.complete();
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          studySettingsRepositoryProvider.overrideWithValue(repository),
        ],
        child: const Cuso4App(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('学习设置'));
    await tester.pumpAndSettle();
    expect(find.byType(StudySettingsPage), findsOneWidget);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  }

  testWidgets(
    'saves all values, reports validation and reveals a folded invalid field',
    (tester) async {
      await open(tester);
      await change(tester, '每日新卡数', '-1');
      await save(tester);
      expect(find.text('请输入 0–9999 的整数'), findsOneWidget);
      expect(repository.saves, 0);
      await change(tester, '每日新卡数', '5');
      await tester.ensureVisible(find.text('FSRS 进阶设置'));
      await tester.tap(find.text('FSRS 进阶设置'));
      await tester.pumpAndSettle();
      await change(tester, '期望保持率', '100');
      await tester.ensureVisible(find.text('FSRS 进阶设置'));
      await tester.tap(find.text('FSRS 进阶设置'));
      await tester.pumpAndSettle();
      await save(tester);
      expect(field('期望保持率'), findsOneWidget);
      expect(find.text('请输入 70–99 的整数'), findsOneWidget);
      expect(repository.saves, 0);
      await change(tester, '期望保持率', '95');
      await change(tester, '每日复习上限', '42');
      await save(tester);
      expect(find.text('已保存，下次进入学习生效。'), findsOneWidget);
      final settings = await tester.runAsync(repository.load);
      expect(
        settings!.toJson(),
        StudySettings(
          dailyNewLimit: 5,
          dailyReviewLimit: 42,
          desiredRetentionPercent: 95,
        ).toJson(),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('学习设置'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(field('每日新卡数')).controller!.text,
        '5',
      );
      expect(tester.takeException(), isNull);
      await close(tester);
    },
  );

  testWidgets('write failure retains input and back asks before discarding', (
    tester,
  ) async {
    await open(tester);
    repository.fail = true;
    await change(tester, '每日新卡数', '8');
    await save(tester);
    expect(find.text('保存失败，输入已保留，请重试。'), findsOneWidget);
    expect(tester.widget<TextFormField>(field('每日新卡数')).controller!.text, '8');
    expect((await tester.runAsync(repository.load))!.dailyNewLimit, 20);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('放弃修改？'), findsOneWidget);
    await tester.tap(find.text('继续编辑'));
    await tester.pumpAndSettle();
    repository.fail = false;
    await save(tester);
    expect((await tester.runAsync(repository.load))!.dailyNewLimit, 8);
    await change(tester, '每日新卡数', '9');
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('放弃修改'));
    await tester.pumpAndSettle();
    expect(find.byType(StudySettingsPage), findsNothing);
    expect((await tester.runAsync(repository.load))!.dailyNewLimit, 8);
    await close(tester);
  });

  testWidgets('saving blocks duplicate writes and leaving', (tester) async {
    await open(tester);
    repository.saving = Completer<void>();
    await change(tester, '每日新卡数', '9');
    await tester.ensureVisible(find.text('保存学习设置'));
    await tester.tap(find.text('保存学习设置'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.saves, 1);
    await tester.tap(find.text('正在保存'));
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 200));
    expect(repository.saves, 1);
    expect(find.byType(StudySettingsPage), findsOneWidget);
    expect(find.text('放弃修改？'), findsNothing);
    repository.saving!.complete();
    await tester.pumpAndSettle();
    expect(find.text('已保存，下次进入学习生效。'), findsOneWidget);
    await close(tester);
  });

  testWidgets(
    'target phone, small phone, large text, dark, landscape and keyboard fit',
    (tester) async {
      await open(tester);
      expect(tester.takeException(), isNull);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      for (final size in [const Size(1125, 2001), const Size(2712, 1220)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('FSRS 进阶设置'));
        await tester.tap(find.text('FSRS 进阶设置'));
        await tester.pumpAndSettle();
        await change(tester, '每日新卡数', '6');
        tester.view.viewInsets = const FakeViewPadding(bottom: 600);
        await tester.pumpAndSettle();
        await save(tester);
        expect(tester.takeException(), isNull);
        tester.view.resetViewInsets();
      }
      addTearDown(tester.view.resetViewInsets);
      await close(tester);
    },
  );
}
