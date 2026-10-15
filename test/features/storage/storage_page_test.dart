import 'package:cuso4_flashcards/app/providers.dart';
import 'package:cuso4_flashcards/app/theme/app_theme.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/media/media_repository.dart';
import 'package:cuso4_flashcards/features/storage/storage_page.dart';
import 'package:cuso4_flashcards/features/storage/storage_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ControlledStorage extends StorageRepository {
  ControlledStorage(AppDatabase db) : super(db, MediaRepository(db));
  int cleaned = 0;
  @override
  Future<StorageSummary> inspect() async => StorageSummary(
    databaseBytes: 912345678,
    mediaBytes: 2123456789,
    unusedBytes: cleaned == 0 ? 300000 : 0,
    unusedCount: cleaned == 0 ? 5 : 0,
    missingCount: 2,
  );
  @override
  Future<StorageCleanup> clean() async {
    cleaned++;
    return const StorageCleanup(5, 300000, 0);
  }
}

void main() {
  testWidgets(
    'large text storage page confirms cleanup and refreshes totals on phone',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final repository = ControlledStorage(db);
      tester.view.physicalSize = const Size(1220, 2712);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            storageRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(theme: AppTheme.dark, home: const StoragePage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('清理未使用媒体'));
      await tester.tap(find.text('清理未使用媒体'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('确认清理'), findsOneWidget);
      expect(repository.cleaned, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(repository.cleaned, 0);
      await tester.tap(find.text('清理未使用媒体'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text('清理'));
      await tester.pumpAndSettle();
      expect(repository.cleaned, 1);
      expect(find.text('0 个文件 · 0.00 MiB'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
