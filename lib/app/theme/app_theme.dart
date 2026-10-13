import 'package:flutter/material.dart';

import 'app_colors.dart';

abstract final class AppTheme {
  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.ink,
          brightness: brightness,
        ).copyWith(
          primary: dark ? AppColors.nightCopper : AppColors.ink,
          onPrimary: dark
              ? AppColors.nightAccentForeground
              : AppColors.accentForeground,
          secondary: dark ? AppColors.nightCopper : AppColors.copper,
          onSecondary: dark
              ? AppColors.nightAccentForeground
              : AppColors.accentForeground,
          surface: dark ? AppColors.nightSurface : AppColors.paper,
          onSurface: dark ? AppColors.nightForeground : AppColors.foreground,
          error: dark ? AppColors.nightDestructive : AppColors.destructive,
          onError: dark
              ? AppColors.nightDestructiveForeground
              : AppColors.destructiveForeground,
        );
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    );
    final buttonStyle = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(48, 52)),
      shape: WidgetStatePropertyAll(shape),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      ),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: dark ? AppColors.night : AppColors.paper,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      filledButtonTheme: FilledButtonThemeData(style: buttonStyle),
      outlinedButtonTheme: OutlinedButtonThemeData(style: buttonStyle),
      textButtonTheme: TextButtonThemeData(style: buttonStyle),
      appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }
}
