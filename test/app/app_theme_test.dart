import 'package:cuso4_flashcards/app/theme/app_colors.dart';
import 'package:cuso4_flashcards/app/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light theme uses the brand foregrounds for surfaces and actions', () {
    final scheme = AppTheme.light.colorScheme;

    expect(scheme.onSurface, AppColors.foreground);
    expect(scheme.onPrimary, AppColors.accentForeground);
    expect(scheme.onSecondary, AppColors.accentForeground);
    expect(scheme.error, AppColors.destructive);
    expect(scheme.onError, AppColors.destructiveForeground);
  });

  test('dark theme uses warm text and dark action foregrounds', () {
    final scheme = AppTheme.dark.colorScheme;

    expect(scheme.onSurface, AppColors.nightForeground);
    expect(scheme.onPrimary, AppColors.nightAccentForeground);
    expect(scheme.onSecondary, AppColors.nightAccentForeground);
    expect(scheme.error, AppColors.nightDestructive);
    expect(scheme.onError, AppColors.nightDestructiveForeground);
  });

  for (final theme in [AppTheme.light, AppTheme.dark]) {
    test('${theme.brightness.name} theme text contrast is at least 4.5:1', () {
      final scheme = theme.colorScheme;
      final pairs = [
        (scheme.onSurface, scheme.surface),
        (scheme.onSurface, theme.scaffoldBackgroundColor),
        (scheme.onPrimary, scheme.primary),
        (scheme.onSecondary, scheme.secondary),
        (scheme.onError, scheme.error),
      ];

      for (final (foreground, background) in pairs) {
        final foregroundLuminance = foreground.computeLuminance();
        final backgroundLuminance = background.computeLuminance();
        final lighter = foregroundLuminance > backgroundLuminance
            ? foregroundLuminance
            : backgroundLuminance;
        final darker = foregroundLuminance < backgroundLuminance
            ? foregroundLuminance
            : backgroundLuminance;

        expect((lighter + 0.05) / (darker + 0.05), greaterThanOrEqualTo(4.5));
      }
    });
  }
}
