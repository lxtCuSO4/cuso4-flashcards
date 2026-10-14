import 'dart:async';
import 'dart:io';

import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/backup/application/backup_controller.dart';
import 'package:cuso4_flashcards/features/backup/data/backup_platform.dart';
import 'package:cuso4_flashcards/features/backup/presentation/backup_page.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class PendingPicker extends BackupPlatform {
  final selection = Completer<File?>();
  @override
  Future<File?> pickRestoreFile() => selection.future;
}

void main() {
  late Directory root;
  late AppDatabase db;
  late BackupController controller;
  late PendingPicker platform;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('cuso4_backup_ui_');
    db = AppDatabase(NativeDatabase.memory());
    platform = PendingPicker();
    controller = BackupController(
      database: () => db,
      root: () async => root,
      platform: platform,
      importBusy: () => false,
      databaseChanged: () {},
    );
  });
  tearDown(() async {
    if (!platform.selection.isCompleted) platform.selection.complete(null);
    controller.dispose();
    await db.close();
    await root.delete(recursive: true);
  });
  Future<void> open(WidgetTester tester) async {
    addTearDown(() async {
      if (!platform.selection.isCompleted) platform.selection.complete(null);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    });
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          backupControllerProvider.overrideWithValue(controller),
        ],
        child: const Cuso4App(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('备份与恢复'));
    await tester.pumpAndSettle();
  }

  testWidgets('settings entry, large text, dark and landscape remain usable', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('导出本地备份'), findsOneWidget);
    await tester.ensureVisible(find.text('选择备份并恢复'));
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1125, 2001);
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(2001, 1125);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('选择备份并恢复'),
      180,
      scrollable: find.byType(Scrollable).last,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });

  testWidgets(
    'busy state blocks back and duplicate actions, canceled picker is safe',
    (tester) async {
      await open(tester);
      await tester.ensureVisible(find.text('选择备份并恢复'));
      await tester.tap(find.text('选择备份并恢复'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(controller.busy, isTrue);
      final scope = tester.widget<PopScope>(find.byType(PopScope).first);
      expect(scope.canPop, isFalse);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      await tester.runAsync(() async {
        platform.selection.complete(null);
        await Future<void>.delayed(const Duration(milliseconds: 30));
      });
      await tester.pumpAndSettle();
      expect(controller.busy, isFalse);
      expect(find.text('已取消选择。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
