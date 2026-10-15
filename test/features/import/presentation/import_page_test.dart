import 'dart:async';
import 'dart:io';

import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/app/theme/app_theme.dart';
import 'package:cuso4_flashcards/features/import/application/import_controller.dart';
import 'package:cuso4_flashcards/features/import/domain/import_progress.dart';
import 'package:cuso4_flashcards/features/import/domain/import_report.dart';
import 'package:cuso4_flashcards/features/import/presentation/import_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'mobile import shows progress, blocks retry, and displays the report',
    (tester) async {
      tester.view.physicalSize = const Size(1220, 2712);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final completion = Completer<ImportReport>();
      final controller = ImportController((
        file, {
        required merge,
        required isCancelled,
        required onProgress,
      }) {
        onProgress(const ImportProgress(ImportPhase.reading));
        return completion.future;
      });
      addTearDown(controller.dispose);
      controller.select(File('chemistry.apkg'));
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            importControllerProvider.overrideWithValue(controller),
            importRecoveryNoticeProvider.overrideWith(
              (ref) => Stream.value(null),
            ),
          ],
          child: MaterialApp(theme: AppTheme.light, home: const ImportPage()),
        ),
      );
      await tester.scrollUntilVisible(find.text('确认并导入'), 300);
      await tester.tap(find.text('确认并导入'));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('取消导入'), 200);
      expect(find.text('读取卡片与安全处理内容'), findsOneWidget);
      expect(find.text('确认并导入'), findsNothing);
      completion.complete(
        const ImportReport(
          decks: 1,
          notes: 2,
          cards: 3,
          media: 1,
          skipped: 1,
          skippedReasons: {'unsupportedTemplate': 1},
          missingMedia: 1,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('导入完成'), findsOneWidget);
      expect(find.text('不支持的字段或自定义模板：1 条'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
