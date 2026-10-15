import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/touhou_tag.dart';
import '../../../core/widgets/pressable_action.dart';
import '../domain/daily_statistics.dart';
import 'learning_calendar.dart';
import 'statistics_charts.dart';

typedef StatisticsQuery = ({StatisticsPeriod period, DateTime? month});

final statisticsProvider = StreamProvider.autoDispose.family(
  (ref, StatisticsQuery query) => ref
      .watch(statisticsRepositoryProvider)
      .watch(period: query.period, month: query.month),
);

class RecordsPage extends ConsumerStatefulWidget {
  const RecordsPage({super.key});
  @override
  ConsumerState<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends ConsumerState<RecordsPage>
    with WidgetsBindingObserver {
  StatisticsPeriod _period = StatisticsPeriod.week;
  DateTime? _month;
  Timer? _midnightTimer;
  DateTime? _timerDay;
  StatisticsQuery get _query => (period: _period, month: _month);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(statisticsProvider(_query));
    }
  }

  void _scheduleRefresh(StatisticsSnapshot snapshot) {
    if (_timerDay == snapshot.nextDayUtc && _midnightTimer?.isActive == true) {
      return;
    }
    _midnightTimer?.cancel();
    _timerDay = snapshot.nextDayUtc;
    final wait =
        snapshot.nextDayUtc.difference(
          ref.read(statisticsRepositoryProvider).nowUtc,
        ) +
        const Duration(seconds: 1);
    _midnightTimer = Timer(wait.isNegative ? Duration.zero : wait, () {
      if (mounted) ref.invalidate(statisticsProvider(_query));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _midnightTimer?.cancel();
    super.dispose();
  }

  Future<void> _details(DateTime date) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _DayDetails(
      date: date,
      query: (period: _period, month: DateTime.utc(date.year, date.month)),
    ),
  );

  String _date(DateTime day) => '${day.year}/${day.month}/${day.day}';
  String _offset(int minutes) {
    final absolute = minutes.abs();
    return 'UTC${minutes < 0 ? '-' : '+'}${(absolute ~/ 60).toString().padLeft(2, '0')}:${(absolute % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final statistics = ref.watch(statisticsProvider(_query));
    return PageFrame(
      title: '记录',
      header: const TouhouTag(TouhouPlace.journal),
      subtitle: '每一次回想，都在这里留下足迹。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () {
                unawaited(FeedbackScope.of(context).tap());
                context.push('/favorites');
              },
              icon: const Icon(Icons.bookmark_border),
              label: const Text('查看收藏'),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final period in StatisticsPeriod.values)
                ChoiceChip(
                  key: ValueKey('statistics-${period.name}'),
                  label: Text(period.label),
                  selected: _period == period,
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  onSelected: (_) {
                    if (_period == period) return;
                    unawaited(FeedbackScope.of(context).tap());
                    setState(() => _period = period);
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),
          statistics.when(
            loading: () =>
                const LinearProgressIndicator(semanticsLabel: '正在读取学习统计'),
            error: (error, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(error is StateError ? error.message : '学习记录读取失败，请重试。'),
                const SizedBox(height: 16),
                PressableAction(
                  label: '重新读取记录',
                  onPressed: () => ref.invalidate(statisticsProvider(_query)),
                ),
              ],
            ),
            data: (snapshot) {
              _scheduleRefresh(snapshot);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${_date(snapshot.rangeStart)}–${_date(snapshot.today)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '所选范围学习 ${snapshot.activeDays} 天 · 当前连续 ${snapshot.streak} 天',
                  ),
                  const SizedBox(height: 20),
                  StatisticsSummary(statistics: snapshot.summary),
                  const SizedBox(height: 24),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: LearningCalendar(
                        snapshot: snapshot,
                        onMonthChanged: (month) =>
                            setState(() => _month = month),
                        onDaySelected: (date) => unawaited(_details(date)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Card(
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: StatisticsCharts(snapshot: snapshot),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text('学习日时区：${_offset(snapshot.offsetMinutes)}，与每日额度一致。'),
                  const SizedBox(height: 12),
                  const ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Text('统计口径'),
                    children: [
                      Text(
                        '学习次数按评分记录计算，卡片张数在所选范围内去重。非重来比例 = 未选“重来”的次数 ÷ 全部评分次数，属于自评结果。\n\n记录耗时可能包含卡片停留和后台时间，不等同于纯专注时长。连续天数从今天起算，今天尚未学习时从昨天起算。\n\n仅统计当前保留的评分记录。撤销评分和删除卡片会同步移除相关统计；导入牌组本身不增加学习记录。',
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DayDetails extends ConsumerWidget {
  const _DayDetails({required this.date, required this.query});
  final DateTime date;
  final StatisticsQuery query;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .85,
    ),
    child: SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${date.year}年${date.month}月${date.day}日',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: '关闭日期详情',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ref
                .watch(statisticsProvider(query))
                .when(
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('当日记录读取失败，请关闭后重试。'),
                  data: (snapshot) {
                    final day = snapshot.days[date] ?? const ReviewStatistics();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (day.reviewCount == 0) ...[
                          const Text('这一天还没有学习记录。'),
                          const SizedBox(height: 16),
                        ],
                        StatisticsSummary(statistics: day),
                        const SizedBox(height: 24),
                        RatingDistribution(statistics: day),
                        const SizedBox(height: 20),
                        const Text('次数按评分计算，卡片按当日去重。非重来比例来自自评，耗时为会话记录值。'),
                      ],
                    );
                  },
                ),
          ],
        ),
      ),
    ),
  );
}
