import 'package:flutter/widgets.dart';

/// Compose with the platform scaler instead of flattening nonlinear scaling.
TextScaler applyFontPercent(TextScaler system, int percent) =>
    percent == 100 ? system : _FontPercentScaler(system, percent / 100);

class _FontPercentScaler extends TextScaler {
  const _FontPercentScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;

  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is _FontPercentScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}

class FontScaleScope extends InheritedWidget {
  const FontScaleScope({
    super.key,
    required this.system,
    required this.cardPercent,
    required super.child,
  });
  final TextScaler system;
  final int cardPercent;

  static TextScaler systemOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FontScaleScope>()?.system ??
      MediaQuery.textScalerOf(context);

  static TextScaler readingOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<FontScaleScope>();
    return scope == null
        ? MediaQuery.textScalerOf(context)
        : applyFontPercent(scope.system, scope.cardPercent);
  }

  @override
  bool updateShouldNotify(FontScaleScope oldWidget) =>
      oldWidget.system != system || oldWidget.cardPercent != cardPercent;
}
