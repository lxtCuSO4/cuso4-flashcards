import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme/lunar_theme.dart';
import '../../../core/widgets/lunar_widgets.dart';
import '../data/practice_statistics_repository.dart';
import '../domain/daily_statistics.dart';
import 'learning_calendar.dart';

typedef PracticeRecordsQuery = ({StatisticsPeriod period, DateTime? month});
final practiceStatisticsProvider = StreamProvider.autoDispose.family(
  (ref, PracticeRecordsQuery query) =>
      PracticeStatisticsRepository(ref.watch(databaseProvider))
          .watch(period: query.period, month: query.month),
);

class PracticeRecordsPanel extends ConsumerStatefulWidget {
  const PracticeRecordsPanel({super.key, required this.period});
  final StatisticsPeriod period;
  @override
  ConsumerState<PracticeRecordsPanel> createState() =>
      _PracticeRecordsPanelState();
}

class _PracticeRecordsPanelState extends ConsumerState<PracticeRecordsPanel>
    with WidgetsBindingObserver {
  DateTime? _month, _scheduled;
  Timer? _midnight;
  PracticeRecordsQuery get _query => (period: widget.period, month: _month);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(practiceStatisticsProvider(_query));
    }
  }

  void _schedule(PracticeStatisticsSnapshot value) {
    final next = value.today
        .add(const Duration(days: 1))
        .subtract(Duration(minutes: value.offset));
    if (_scheduled == next && _midnight?.isActive == true) return;
    _midnight?.cancel();
    _scheduled = next;
    final wait =
        next.difference(DateTime.now().toUtc()) + const Duration(seconds: 1);
    _midnight = Timer(wait.isNegative ? const Duration(seconds: 1) : wait, () {
      if (mounted) ref.invalidate(practiceStatisticsProvider(_query));
    });
  }

  String _duration(int milliseconds) {
    final seconds = milliseconds ~/ 1000;
    return seconds < 60 ? '$seconds 秒' : '${seconds ~/ 60} 分';
  }

  Future<void> _day(DateTime day, int offset) => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => LunarSurface(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .78,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${day.year}年${day.month}月${day.day}日 · 刷题记录',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭刷题详情',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: PracticeStatisticsRepository(
                    ref.read(databaseProvider),
                  ).dayDetails(day, offset),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Center(child: Text('刷题详情读取失败，请重试'));
                    }
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final rows = snapshot.data!;
                    if (rows.isEmpty) {
                      return const Center(child: Text('当天没有选择题提交记录'));
                    }
                    return ListView.separated(
                      itemCount: rows.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, index) {
                        final row = rows[index];
                        final time = DateTime.fromMillisecondsSinceEpoch(
                          row['submittedAtUtc'] as int,
                          isUtc: true,
                        ).add(Duration(minutes: offset));
                        final source = switch (row['source']) {
                          'wrong' => '错题练习',
                          'favorites' => '收藏练习',
                          _ => '牌组练习',
                        };
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            (row['prompt'] as String?)?.isNotEmpty == true
                                ? row['prompt'] as String
                                : '题目 #${row['cardId']}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            '$source · ${row['sourceDeckName'] ?? row['deckName']} · ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                          ),
                          trailing: Text(
                            row['correct'] == true ? '答对' : '答错',
                            style: TextStyle(
                              color: row['correct'] == true
                                  ? LunarPalette.of(context).jade
                                  : Theme.of(context).colorScheme.error,
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => ref
      .watch(practiceStatisticsProvider(_query))
      .when(
        loading: () => const LinearProgressIndicator(),
        error: (_, _) => Column(
          children: [
            const Text('刷题统计读取失败'),
            TextButton(
              onPressed: () =>
                  ref.invalidate(practiceStatisticsProvider(_query)),
              child: const Text('重试读取刷题统计'),
            ),
          ],
        ),
        data: (value) {
          _schedule(value);
          final s = value.summary;
          final rate = s.accuracy == null
              ? '暂无作答'
              : '正确率 ${(s.accuracy! * 100).toStringAsFixed(1)}%';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LunarHero(
                label: '选择题练习 · ${widget.period.label}',
                value: '${s.answered}',
                unit: '题次',
                fullMoon: true,
                subtitle: rate,
              ),
              const SizedBox(height: 16),
              LunarStats([
                ('答对', '${s.correct}'),
                ('答错', '${s.wrong}'),
                ('前台用时', _duration(s.elapsedMs)),
              ]),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: LearningCalendar(
                    snapshot: value.calendar,
                    title: '刷题日历',
                    countLabel: '作答',
                    onMonthChanged: (month) => setState(() => _month = month),
                    onDaySelected: (day) => unawaited(_day(day, value.offset)),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '选择题仅真实提交计入题次；查看解析、回看和跳转不重复计分。历史统计从本版本开始记录，不补造旧版数据。',
                style: TextStyle(fontSize: 12, height: 1.6),
              ),
            ],
          );
        },
      );
}
