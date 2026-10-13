import 'package:cuso4_flashcards/core/feedback/feedback_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';

class RecordingFeedbackPlatform implements FeedbackPlatform {
  final calls = <FeedbackKind>[];
  @override
  Future<void> perform(FeedbackKind kind) async => calls.add(kind);
}

class UnsupportedFeedbackPlatform implements FeedbackPlatform {
  UnsupportedFeedbackPlatform(this.failure);
  final Object failure;
  @override
  Future<void> perform(FeedbackKind kind) async => throw failure;
}

void main() {
  for (final strength in FeedbackStrength.values) {
    test('review confirmation respects $strength', () async {
      final platform = RecordingFeedbackPlatform();
      final controller = FeedbackController(
        platform: platform,
        strength: strength,
      );
      await controller.confirmReview();
      expect(platform.calls, switch (strength) {
        FeedbackStrength.strong => [FeedbackKind.mediumImpact],
        FeedbackStrength.gentle => [FeedbackKind.lightImpact],
        FeedbackStrength.off => <FeedbackKind>[],
      });
    });
  }
  test(
    'tap, destructive confirmation and errors have distinct feedback',
    () async {
      final platform = RecordingFeedbackPlatform();
      final controller = FeedbackController(platform: platform);
      await controller.tap();
      await controller.destructiveConfirm();
      await controller.error();
      expect(platform.calls, [
        FeedbackKind.selection,
        FeedbackKind.mediumImpact,
        FeedbackKind.error,
      ]);
    },
  );
  for (final strength in FeedbackStrength.values) {
    test('all feedback respects $strength', () async {
      final platform = RecordingFeedbackPlatform();
      final controller = FeedbackController(
        platform: platform,
        strength: strength,
      );
      await controller.tap();
      await controller.confirmReview();
      await controller.destructiveConfirm();
      await controller.error();
      expect(platform.calls, switch (strength) {
        FeedbackStrength.strong => [
          FeedbackKind.selection,
          FeedbackKind.mediumImpact,
          FeedbackKind.mediumImpact,
          FeedbackKind.error,
        ],
        FeedbackStrength.gentle => [
          FeedbackKind.selection,
          FeedbackKind.lightImpact,
          FeedbackKind.lightImpact,
          FeedbackKind.lightImpact,
        ],
        FeedbackStrength.off => <FeedbackKind>[],
      });
    });
  }
  for (final failure in [
    MissingPluginException(),
    PlatformException(code: 'unsupported'),
    UnsupportedError('No haptics'),
  ]) {
    test(
      'unsupported haptics are best effort: ${failure.runtimeType}',
      () async {
        final controller = FeedbackController(
          platform: UnsupportedFeedbackPlatform(failure),
        );
        await controller.tap();
        await controller.confirmReview();
        await controller.destructiveConfirm();
        await controller.error();
      },
    );
  }
  test('Flutter platform maps each feedback kind to haptics', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          calls.add(call);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final platform = FlutterFeedbackPlatform();
    for (final kind in FeedbackKind.values) {
      await platform.perform(kind);
    }
    expect(
      calls.map((call) => call.method),
      everyElement('HapticFeedback.vibrate'),
    );
    expect(calls.map((call) => call.arguments), [
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      null,
    ]);
  });
}
