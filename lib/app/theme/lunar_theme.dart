import 'package:flutter/material.dart';

import 'app_theme.dart';

class LunarPalette {
  const LunarPalette({
    required this.paper,
    required this.surface,
    required this.ink,
    required this.muted,
    required this.jade,
    required this.onJade,
    required this.wash,
    required this.line,
    required this.night,
    required this.moon,
    required this.gold,
  });
  final Color paper,
      surface,
      ink,
      muted,
      jade,
      onJade,
      wash,
      line,
      night,
      moon,
      gold;
  static const light = LunarPalette(
    paper: Color(0xFFF2F1EB),
    surface: Color(0xFFFDFCF8),
    ink: Color(0xFF253B3E),
    muted: Color(0xFF5B6E70),
    jade: Color(0xFF30595B),
    onJade: Color(0xFFFFFDF5),
    wash: Color(0xFFE5EEEA),
    line: Color(0xFFD7DFDA),
    night: Color(0xFF244449),
    moon: Color(0xFFEEE7D2),
    gold: Color(0xFF8B7044),
  );
  static const dark = LunarPalette(
    paper: Color(0xFF131E23),
    surface: Color(0xFF1D2B30),
    ink: Color(0xFFE5ECE7),
    muted: Color(0xFFADBFBC),
    jade: Color(0xFFB0D0C2),
    onJade: Color(0xFF172C2A),
    wash: Color(0xFF293E3C),
    line: Color(0xFF374B4E),
    night: Color(0xFF203A40),
    moon: Color(0xFFE4DEC9),
    gold: Color(0xFFD3BD8E),
  );
  static LunarPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;
}

class LunarScope extends InheritedWidget {
  const LunarScope({super.key, required this.exterior, required super.child});
  final bool exterior;
  static bool isExterior(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LunarScope>()?.exterior ??
      false;
  @override
  bool updateShouldNotify(LunarScope oldWidget) =>
      exterior != oldWidget.exterior;
}

class LunarTheme {
  static final light = _build(Brightness.light);
  static final dark = _build(Brightness.dark);
  static ThemeData _build(Brightness brightness) {
    final p = brightness == Brightness.dark
        ? LunarPalette.dark
        : LunarPalette.light;
    final base = brightness == Brightness.dark ? AppTheme.dark : AppTheme.light;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    return base.copyWith(
      colorScheme: base.colorScheme.copyWith(
        primary: p.jade,
        onPrimary: p.onJade,
        primaryContainer: p.wash,
        onPrimaryContainer: p.ink,
        secondary: p.gold,
        surface: p.surface,
        onSurface: p.ink,
        onSurfaceVariant: p.muted,
        outline: p.muted,
        outlineVariant: p.line,
        surfaceContainerLow: p.paper,
        surfaceContainer: p.wash,
        surfaceContainerHighest: p.wash,
      ),
      scaffoldBackgroundColor: p.paper,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: p.paper,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          color: p.ink,
          fontSize: 20,
          fontWeight: FontWeight.w500,
        ),
      ),
      cardTheme: CardThemeData(
        color: p.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: p.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: p.jade, width: 1.5),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.ink,
          minimumSize: const Size(48, 48),
          shape: shape,
          side: BorderSide(color: p.line),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: shape,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: p.wash,
        height: 76,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(color: p.ink, fontSize: 12),
        ),
      ),
      dividerColor: p.line,
    );
  }
}

class LunarSurface extends StatelessWidget {
  const LunarSurface({super.key, required this.child, this.exterior = true});
  final Widget child;
  final bool exterior;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Theme(
      data: exterior
          ? (dark ? LunarTheme.dark : LunarTheme.light)
          : (dark ? AppTheme.dark : AppTheme.light),
      child: LunarScope(exterior: exterior, child: child),
    );
  }
}
