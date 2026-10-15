import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/feedback/feedback_controller.dart';
import '../domain/daily_statistics.dart';

class LearningCalendar extends StatelessWidget {
  const LearningCalendar({
    super.key,
    required this.snapshot,
    required this.onMonthChanged,
    required this.onDaySelected,
  });
  final StatisticsSnapshot snapshot;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<DateTime> onDaySelected;

  void _month(BuildContext context, DateTime value) {
    unawaited(FeedbackScope.of(context).tap());
    onMonthChanged(value);
  }

  Color _color(ColorScheme scheme, int count) {
    final level = count == 0
        ? 0.0
        : count < 10
        ? .35
        : count < 30
        ? .65
        : 1.0;
    return Color.lerp(
      scheme.surfaceContainerLow,
      scheme.primaryContainer,
      level,
    )!;
  }

  @override
  Widget build(BuildContext context) {
    final month = snapshot.month;
    final currentMonth = DateTime.utc(
      snapshot.today.year,
      snapshot.today.month,
    );
    final previous = DateTime.utc(month.year, month.month - 1);
    final next = DateTime.utc(month.year, month.month + 1);
    final offset = month.weekday - 1;
    final count = DateTime.utc(month.year, month.month + 1, 0).day;
    final rows = ((offset + count) / 7).ceil();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('学习日历', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Row(
                children: [
                  IconButton(
                    tooltip: '上个月',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: month.year > 1 || month.month > 1
                        ? () => _month(context, previous)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text(
                        '${month.year}年${month.month}月',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '下个月',
                    constraints: const BoxConstraints(
                      minWidth: 48,
                      minHeight: 48,
                    ),
                    onPressed: next.isAfter(currentMonth)
                        ? null
                        : () => _month(context, next),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: month == currentMonth
                      ? null
                      : () => _month(context, currentMonth),
                  child: const Text('回到本月'),
                ),
              ),
            ],
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final width = math.max(336.0, constraints.maxWidth);
            final cellHeight = math.max(
              48.0,
              MediaQuery.textScalerOf(context).scale(16) + 24,
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (constraints.maxWidth < 336)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('左右滑动日历查看完整一周。'),
                  ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: width,
                    child: Column(
                      children: [
                        Row(
                          children: [
                            for (final day in [
                              '一',
                              '二',
                              '三',
                              '四',
                              '五',
                              '六',
                              '日',
                            ])
                              Expanded(child: Center(child: Text(day))),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (var row = 0; row < rows; row++)
                          Row(
                            children: [
                              for (var column = 0; column < 7; column++)
                                Expanded(
                                  child: SizedBox(
                                    height: cellHeight,
                                    child: _day(
                                      context,
                                      row * 7 + column - offset + 1,
                                      count,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('点日期查看详情，边框标出今天。'),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  for (final value in [
                    (0, '0 次'),
                    (1, '1–9 次'),
                    (10, '10–29 次'),
                    (30, '30+ 次'),
                  ])
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: _color(scheme, value.$1),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: scheme.outline),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(value.$2),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _day(BuildContext context, int number, int count) {
    if (number < 1 || number > count) return const SizedBox();
    final date = DateTime.utc(
      snapshot.month.year,
      snapshot.month.month,
      number,
    );
    final reviews = snapshot.days[date]?.reviewCount ?? 0;
    final future = date.isAfter(snapshot.today);
    final today = date == snapshot.today;
    final scheme = Theme.of(context).colorScheme;
    void activate() {
      unawaited(FeedbackScope.of(context).tap());
      onDaySelected(date);
    }

    return Semantics(
      button: !future,
      enabled: !future,
      onTap: future ? null : activate,
      label:
          '${date.year}年${date.month}月${date.day}日，${future ? '尚未到来' : '学习 $reviews 次'}${today ? '，今天' : ''}',
      child: ExcludeSemantics(
        child: InkWell(
          key: ValueKey('calendar-${date.year}-${date.month}-${date.day}'),
          onTap: future ? null : activate,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(2),
            child: Ink(
              decoration: BoxDecoration(
                color: _color(scheme, reviews),
                borderRadius: BorderRadius.circular(10),
                border: today
                    ? Border.all(color: scheme.primary, width: 2)
                    : null,
              ),
              child: Center(
                child: Text(
                  '$number',
                  style: TextStyle(
                    color: future ? scheme.onSurfaceVariant : scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
