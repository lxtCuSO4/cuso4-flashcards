import 'package:flutter/material.dart';

import '../domain/home_summary.dart';

class TodayOverview extends StatelessWidget {
  const TodayOverview({super.key, required this.summary});
  final HomeSummary summary;

  @override
  Widget build(BuildContext context) {
    final availability = summary.availability;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final today = availability.today;
    final next = availability.nextDueAtUtc?.add(
      Duration(minutes: availability.offsetMinutes),
    );
    final status = availability.availableCards > 0
        ? '按到期时间和各牌组剩余额度计算。'
        : availability.blockedCards > 0
        ? '有 ${availability.blockedCards} 张到期卡受今日额度限制，可在学习设置中调整。'
        : '当前没有已到期卡片，稍后再来。';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(28),
          ),
          child: DefaultTextStyle.merge(
            style: TextStyle(color: scheme.onPrimaryContainer),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${today.month}月${today.day}日 · 今日',
                  style: textTheme.titleMedium?.copyWith(
                    color: scheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 24),
                const Text('现在可学'),
                const SizedBox(height: 4),
                Semantics(
                  label: '现在可学，${availability.availableCards} 张',
                  child: ExcludeSemantics(
                    child: Text(
                      '${availability.availableCards} 张',
                      style: textTheme.displayMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(status),
                if (next != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '下次到期：${next.month}月${next.day}日 ${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}（学习日时区）',
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final columns = ((constraints.maxWidth + 12) / (100 * scale + 12))
                .floor()
                .clamp(1, 3);
            final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final (label, count, icon) in [
                  ('待复习', availability.reviews, Icons.history_outlined),
                  ('学习中', availability.learning, Icons.autorenew_outlined),
                  ('可学新卡', availability.newCards, Icons.auto_awesome_outlined),
                ])
                  SizedBox(
                    width: width,
                    child: Semantics(
                      label: '$label，$count 张',
                      child: ExcludeSemantics(
                        child: Card(
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(icon, color: scheme.primary, size: 24),
                                const SizedBox(height: 12),
                                Text(label, style: textTheme.bodyMedium),
                                const SizedBox(height: 4),
                                Text(
                                  '$count 张',
                                  style: textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
