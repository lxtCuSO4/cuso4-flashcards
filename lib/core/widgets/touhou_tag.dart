import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';

enum TouhouPlace {
  school('寺子屋', Icons.menu_book_outlined),
  library('寺子屋 · 藏书', Icons.auto_stories_outlined),
  study('寺子屋 · 温习', Icons.menu_book_outlined),
  bamboo('迷途竹林', Icons.park_outlined),
  journal('月下手记', Icons.nights_stay_outlined),
  eientei('永远亭', Icons.nights_stay_outlined),
  bookmarks('铃仙的书签', Icons.bookmark_border_rounded);

  const TouhouPlace(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// Fixed page decoration, independent of settings and card content.
class TouhouTag extends StatelessWidget {
  const TouhouTag(
    this.place, {
    super.key,
    this.margin = const EdgeInsets.only(bottom: 16),
  });

  final TouhouPlace place;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final foreground = dark
        ? AppColors.nightTouhouForeground
        : AppColors.touhouForeground;
    return ExcludeSemantics(
      child: Padding(
        padding: margin,
        child: Align(
          alignment: Alignment.centerLeft,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: dark
                  ? AppColors.nightTouhouSurface
                  : AppColors.touhouSurface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(place.icon, size: 14, color: foreground),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      place.label,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
