import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/lunar_theme.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../data/practice_session_repository.dart';
import '../domain/practice_session.dart';

class PracticeAnswerSheet extends StatefulWidget {
  const PracticeAnswerSheet({
    super.key,
    required this.session,
    required this.repository,
  });
  final PracticeSession session;
  final PracticeSessionRepository repository;
  @override
  State<PracticeAnswerSheet> createState() => _PracticeAnswerSheetState();
}

class _PracticeAnswerSheetState extends State<PracticeAnswerSheet> {
  late final _answers = widget.repository.answers(widget.session);
  String _filter = '全部';
  @override
  Widget build(BuildContext context) {
    final p = LunarPalette.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .82,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '本轮答题卡',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500),
                  ),
                ),
                IconButton(
                  tooltip: '关闭答题卡',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: FutureBuilder<List<PracticeAnswer>>(
                future: _answers,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Center(child: Text('答题卡读取失败，请关闭后重试'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final items = snapshot.data!
                      .where(
                        (a) => switch (_filter) {
                          '未答' =>
                            a.status == PracticeAnswerStatus.pending ||
                                a.status == PracticeAnswerStatus.skipped,
                          '答错' => a.status == PracticeAnswerStatus.wrong,
                          '收藏' => a.favorite,
                          _ => true,
                        },
                      )
                      .toList();
                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              widget.session.round.deckName,
                              style: TextStyle(color: p.muted),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                for (final filter in ['全部', '未答', '答错', '收藏'])
                                  ChoiceChip(
                                    label: Text(filter),
                                    selected: filter == _filter,
                                    onSelected: (_) {
                                      unawaited(
                                        FeedbackScope.of(context).tap(),
                                      );
                                      setState(() => _filter = filter);
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (widget.session.round.legacyBefore > 0) ...[
                              const Text(
                                '旧版仅保存进度，之前的题目显示“已练习”，没有历史答案',
                                style: TextStyle(fontSize: 12, height: 1.5),
                              ),
                              const SizedBox(height: 10),
                            ],
                            const Text(
                              '点选题号跳转；回看已答题不会重复计分',
                              style: TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 12,
                              runSpacing: 8,
                              children: [
                                for (final (icon, label) in [
                                  (Icons.check, '答对'),
                                  (Icons.close, '答错'),
                                  (Icons.visibility_outlined, '已看答案'),
                                  (Icons.more_horiz, '未答'),
                                ])
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(icon, size: 14, color: p.muted),
                                      const SizedBox(width: 4),
                                      Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: p.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                      if (items.isEmpty)
                        const SliverToBoxAdapter(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('当前筛选下没有题目'),
                          ),
                        )
                      else
                        SliverGrid(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _tile(context, items[index]),
                            childCount: items.length,
                          ),
                          gridDelegate:
                              SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 78,
                                mainAxisExtent: math.max(
                                  66,
                                  MediaQuery.textScalerOf(context).scale(18) +
                                      26,
                                ),
                                mainAxisSpacing: 9,
                                crossAxisSpacing: 9,
                              ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(BuildContext context, PracticeAnswer a) {
    final p = LunarPalette.of(context);
    final current =
        a.index == widget.session.index && !widget.session.completed;
    final color = a.status == PracticeAnswerStatus.wrong
        ? Theme.of(context).colorScheme.error
        : a.status == PracticeAnswerStatus.correct
        ? p.jade
        : p.muted;
    final icon = switch (a.status) {
      PracticeAnswerStatus.correct => Icons.check,
      PracticeAnswerStatus.wrong => Icons.close,
      PracticeAnswerStatus.viewed => Icons.visibility_outlined,
      PracticeAnswerStatus.skipped => Icons.skip_next_outlined,
      PracticeAnswerStatus.legacy => Icons.history,
      PracticeAnswerStatus.pending => null,
    };
    return Semantics(
      button: true,
      selected: current,
      label: '第 ${a.index + 1} 题，${a.label}${a.favorite ? '，已收藏' : ''}',
      child: Material(
        color: color.withValues(alpha: .09),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
          side: BorderSide(
            color: current ? p.jade : Colors.transparent,
            width: 1.5,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('answer-sheet-${a.index}'),
          onTap: () {
            unawaited(FeedbackScope.of(context).tap());
            Navigator.pop(context, a.index);
          },
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      child: Text(
                        '${a.index + 1}',
                        style: TextStyle(color: color, fontSize: 18),
                      ),
                    ),
                    if (icon != null) Icon(icon, size: 14, color: color),
                  ],
                ),
              ),
              if (a.favorite)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Icon(Icons.bookmark, size: 12, color: p.gold),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
