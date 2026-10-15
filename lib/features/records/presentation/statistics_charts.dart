import 'package:flutter/material.dart';

import '../../study/domain/scheduler.dart';
import '../domain/daily_statistics.dart';

String recordedDurationLabel(Duration elapsed) {
  if (elapsed == Duration.zero) return '0 秒';
  if (elapsed.inSeconds == 0) return '不足 1 秒';
  if (elapsed.inMinutes == 0) return '${elapsed.inSeconds} 秒';
  if (elapsed.inHours == 0) {
    return '${elapsed.inMinutes} 分 ${elapsed.inSeconds % 60} 秒';
  }
  return '${elapsed.inHours} 小时 ${elapsed.inMinutes % 60} 分';
}

String rateLabel(double? rate) =>
    rate == null ? '—' : '${(rate * 100).toStringAsFixed(1)}%';

class StatisticsSummary extends StatelessWidget {
  const StatisticsSummary({super.key, required this.statistics});
  final ReviewStatistics statistics;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final twoColumns =
          constraints.maxWidth >= 300 &&
          MediaQuery.textScalerOf(context).scale(16) < 25;
      final width = twoColumns
          ? (constraints.maxWidth - 12) / 2
          : constraints.maxWidth;
      final values = [
        ('学习次数', '${statistics.reviewCount} 次'),
        ('学习卡片', '${statistics.cardCount} 张'),
        ('记录耗时', recordedDurationLabel(statistics.elapsed)),
        ('非重来比例', rateLabel(statistics.successRate)),
      ];
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final value in values)
            SizedBox(
              width: width,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value.$1,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        value.$2,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
}

class RatingDistribution extends StatelessWidget {
  const RatingDistribution({super.key, required this.statistics});
  final ReviewStatistics statistics;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('评分分布', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 16),
      for (var index = 0; index < 4; index++) ...[
        _CountBar(
          label: ReviewRating.values[index].label,
          count: statistics.ratingCounts[index],
          maximum: statistics.reviewCount,
        ),
        if (index != 3) const SizedBox(height: 16),
      ],
    ],
  );
}

class StatisticsCharts extends StatelessWidget {
  const StatisticsCharts({super.key, required this.snapshot});
  final StatisticsSnapshot snapshot;

  String _date(DateTime day) => '${day.year}/${day.month}/${day.day}';

  @override
  Widget build(BuildContext context) {
    final maxCount = snapshot.trend.fold<int>(
      0,
      (largest, b) => b.reviewCount > largest ? b.reviewCount : largest,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('学习趋势', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('按下列日期分段汇总学习次数，包含未学习的日期。'),
        const SizedBox(height: 20),
        if (maxCount == 0)
          const Text('这段时间还没有学习记录。完成一次评分，就会留下第一笔足迹。')
        else
          for (final bucket in snapshot.trend) ...[
            _CountBar(
              label: bucket.start == bucket.end
                  ? _date(bucket.start)
                  : '${_date(bucket.start)}–${_date(bucket.end)}',
              count: bucket.reviewCount,
              maximum: maxCount,
            ),
            const SizedBox(height: 16),
          ],
        const SizedBox(height: 16),
        RatingDistribution(statistics: snapshot.summary),
      ],
    );
  }
}

class _CountBar extends StatelessWidget {
  const _CountBar({
    required this.label,
    required this.count,
    required this.maximum,
  });
  final String label;
  final int count;
  final int maximum;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label，$count 次',
    child: ExcludeSemantics(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            children: [Text(label), Text('$count 次')],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: maximum == 0 ? 0 : count / maximum,
            minHeight: 8,
            borderRadius: BorderRadius.circular(8),
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest,
          ),
        ],
      ),
    ),
  );
}
