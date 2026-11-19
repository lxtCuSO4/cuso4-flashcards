import 'dart:math';

import 'package:cuso4_flashcards/app/theme/app_theme.dart';
import 'package:cuso4_flashcards/features/study/domain/scheduler.dart';
import 'package:cuso4_flashcards/features/study/presentation/review_rating_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('each rating retains readable foreground in both themes', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      await tester.pumpWidget(
        MaterialApp(
          theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: Scaffold(
            body: ReviewRatingBar(
              intervals: {
                for (final rating in ReviewRating.values)
                  rating: const Duration(days: 1),
              },
              onRate: (_) async {},
            ),
          ),
        ),
      );
      for (final rating in ReviewRating.values) {
        final element = tester.element(
          find.byKey(ValueKey('rating-${rating.name}')),
        );
        final colors = Theme.of(element).colorScheme;
        final foreground = colors.onPrimary.computeLuminance();
        final background = colors.primary.computeLuminance();
        final contrast =
            (max(foreground, background) + .05) /
            (min(foreground, background) + .05);
        expect(
          contrast,
          greaterThanOrEqualTo(4.5),
          reason: '${brightness.name}/${rating.name}',
        );
      }
    }
  });
}
