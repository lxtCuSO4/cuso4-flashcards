import 'dart:convert';

import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/app/theme/app_theme.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/features/import/domain/import_recovery_notice.dart';
import 'package:cuso4_flashcards/features/import/presentation/import_recovery_notice.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'recovery retry and persistent acknowledgement fit a dark large-text phone',
    (tester) async {
      tester.view.physicalSize = const Size(1220, 2712);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: ImportRecoveryNotice.settingKey,
              valueJson: jsonEncode({
                'version': 1,
                'generation': 1,
                'interruptedJobs': 2,
                'cleanupFailures': 1,
              }),
            ),
          );
      var retries = 0;
      Widget app() => ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.8),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: Scaffold(
            body: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ImportRecoveryBanner(
                  onRetry: () {
                    retries++;
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('上次导入未完成'), findsOneWidget);
      expect(find.textContaining('2 次导入意外中断'), findsOneWidget);
      expect(find.textContaining('1 处临时文件'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('前往导入'));
      await tester.tap(find.text('前往导入'));
      await tester.pumpAndSettle();
      expect(retries, 1);
      await tester.ensureVisible(find.text('知道了'));
      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
      expect(find.text('上次导入未完成'), findsNothing);
      expect(await db.select(db.appSettings).get(), isEmpty);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      await tester.pumpWidget(app());
      await tester.pumpAndSettle();
      expect(find.text('上次导入未完成'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
