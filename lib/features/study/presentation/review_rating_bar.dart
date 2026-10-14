import 'package:flutter/material.dart';

import '../../../core/widgets/pressable_action.dart';
import '../domain/scheduler.dart';

String formatReviewInterval(Duration duration) {
  if (duration.inMinutes < 1) return '不到 1 分钟';
  if (duration.inHours < 1) return '${duration.inMinutes} 分钟';
  if (duration.inDays < 1) return '${duration.inHours} 小时';
  if (duration.inDays < 30) return '${duration.inDays} 天';
  if (duration.inDays < 365) {
    return '${(duration.inDays / 30).toStringAsFixed(1)} 个月';
  }
  return '${(duration.inDays / 365).toStringAsFixed(1)} 年';
}

class ReviewRatingBar extends StatelessWidget {
  const ReviewRatingBar({
    super.key,
    required this.intervals,
    required this.onRate,
  });
  final Map<ReviewRating, Duration> intervals;
  final Future<void> Function(ReviewRating)? onRate;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final columns =
          box.maxWidth >= 600 &&
              MediaQuery.textScalerOf(context).scale(14) <= 21
          ? 4
          : 2;
      final width = (box.maxWidth - (columns - 1) * 10) / columns;
      final scheme = Theme.of(context).colorScheme;
      final colors = [
        scheme.error,
        const Color(0xFFE9BC77),
        scheme.primary,
        const Color(0xFF91D6B0),
      ];
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final rating in ReviewRating.values)
            SizedBox(
              width: width,
              child: Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: scheme.copyWith(
                    primary: colors[rating.index],
                    onPrimary: const Color(0xFF14251F),
                  ),
                ),
                child: PressableAction(
                  key: ValueKey('rating-${rating.name}'),
                  reviewFeedback: true,
                  label:
                      '${rating.label}\n${formatReviewInterval(intervals[rating] ?? Duration.zero)}',
                  onPressed: onRate == null ? null : () => onRate!(rating),
                ),
              ),
            ),
        ],
      );
    },
  );
}
