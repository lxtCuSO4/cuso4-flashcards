import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum FeedbackStrength { strong, gentle, off }

enum FeedbackKind { selection, lightImpact, mediumImpact, error }

class FeedbackScope extends InheritedWidget {
  const FeedbackScope({
    super.key,
    required this.controller,
    required super.child,
  });
  final FeedbackController controller;
  static FeedbackController of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FeedbackScope>()?.controller ??
      const FeedbackController();
  @override
  bool updateShouldNotify(FeedbackScope oldWidget) =>
      controller.strength != oldWidget.controller.strength;
}

abstract interface class FeedbackPlatform {
  Future<void> perform(FeedbackKind kind);
}

class FlutterFeedbackPlatform implements FeedbackPlatform {
  const FlutterFeedbackPlatform();

  @override
  Future<void> perform(FeedbackKind kind) => switch (kind) {
    FeedbackKind.selection => HapticFeedback.selectionClick(),
    FeedbackKind.lightImpact => HapticFeedback.lightImpact(),
    FeedbackKind.mediumImpact => HapticFeedback.mediumImpact(),
    FeedbackKind.error => HapticFeedback.vibrate(),
  };
}

/// Optional haptics never determine whether a business action can run.
class FeedbackController {
  const FeedbackController({
    this.platform = const FlutterFeedbackPlatform(),
    this.strength = FeedbackStrength.strong,
  });

  final FeedbackPlatform platform;
  final FeedbackStrength strength;

  Future<void> tap() => _perform(FeedbackKind.selection);

  Future<void> confirmReview() => _perform(FeedbackKind.mediumImpact);

  Future<void> destructiveConfirm() => _perform(FeedbackKind.mediumImpact);

  Future<void> error() => _perform(FeedbackKind.error);

  Future<void> _perform(FeedbackKind kind) async {
    if (strength == FeedbackStrength.off) return;
    final effectiveKind =
        strength == FeedbackStrength.gentle && kind != FeedbackKind.selection
        ? FeedbackKind.lightImpact
        : kind;
    try {
      await platform.perform(effectiveKind);
    } catch (_) {
      // Haptics are best effort on devices and hosts without support.
    }
  }
}
