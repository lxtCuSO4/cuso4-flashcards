import 'dart:async';
import 'dart:io';

import 'package:cuso4_flashcards/features/import/application/import_controller.dart';
import 'package:cuso4_flashcards/features/import/domain/import_error.dart';
import 'package:cuso4_flashcards/features/import/domain/import_progress.dart';
import 'package:cuso4_flashcards/features/import/domain/import_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('blocks duplicate starts and keeps cancellation pending until rollback ends', () async {
    final completion = Completer<ImportReport>();
    var calls = 0;
    late bool Function() cancellation;
    final controller = ImportController((
      file, {
      required merge,
      required isCancelled,
      required onProgress,
    }) {
      calls++;
      cancellation = isCancelled;
      onProgress(const ImportProgress(ImportPhase.reading));
      return completion.future;
    });
    controller.select(File('deck.apkg'));
    final first = controller.start();
    await controller.start();
    expect(calls, 1);
    expect(controller.busy, isTrue);
    controller.cancel();
    expect(cancellation(), isTrue);
    expect(controller.busy, isTrue);
    completion.completeError(
      const ApkgImportException(ImportErrorCode.cancelled, '已取消'),
    );
    await first;
    expect(controller.busy, isFalse);
    expect(controller.error, '已取消');
    expect(controller.report, isNull);
    controller.dispose();
  });
}
