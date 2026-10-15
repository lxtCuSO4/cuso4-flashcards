import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/touhou_tag.dart';
import '../../../core/widgets/pressable_action.dart';
import '../../import/presentation/import_recovery_notice.dart';
import '../domain/home_summary.dart';
import 'today_overview.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});
  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage>
    with WidgetsBindingObserver {
  Timer? _refreshTimer;
  DateTime? _refreshAt;
  bool _creatingCard = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) ref.invalidate(homeSummaryProvider);
  }

  void _scheduleRefresh(HomeSummary summary) {
    final at = summary.availability.refreshAtUtc;
    if (_refreshAt == at && _refreshTimer?.isActive == true) return;
    _refreshTimer?.cancel();
    _refreshAt = at;
    final wait =
        at.difference(ref.read(homeSummaryServiceProvider).nowUtc) +
        const Duration(seconds: 1);
    _refreshTimer = Timer(
      wait.isNegative ? const Duration(seconds: 1) : wait,
      () {
        if (mounted) ref.invalidate(homeSummaryProvider);
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _go(String path, {bool replace = false}) {
    unawaited(FeedbackScope.of(context).tap());
    if (replace) {
      context.go(path);
    } else {
      context.push(path);
    }
  }

  Future<void> _createCard(HomeSummary summary) async {
    if (_creatingCard) return;
    setState(() => _creatingCard = true);
    try {
      int deck;
      if (summary.decks.isNotEmpty) {
        deck = summary.decks.first.id;
      } else {
        final name = await requestName(context, '新建牌组');
        if (name == null || !mounted) return;
        deck = await ref.read(deckRepositoryProvider).createDeck(name);
      }
      if (mounted) await context.push('/decks/$deck/new');
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      if (mounted) setState(() => _creatingCard = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(homeSummaryProvider);
    final scheme = Theme.of(context).colorScheme;
    return PageFrame(
      title: 'Lunar Memory',
      titleLeading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.asset(
          'assets/branding/app-logo.png',
          width: 36,
          height: 36,
          filterQuality: FilterQuality.none,
          excludeFromSemantics: true,
        ),
      ),
      header: const TouhouTag(TouhouPlace.school),
      subtitle: '今天，也为记忆留一点时间。',
      actions: [
        IconButton(
          tooltip: '刷新今日概览',
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () {
            unawaited(FeedbackScope.of(context).tap());
            ref.invalidate(homeSummaryProvider);
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ImportRecoveryBanner(onRetry: () => context.push('/import')),
          summary.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Column(
                children: [
                  LinearProgressIndicator(semanticsLabel: '正在读取今日概览'),
                  SizedBox(height: 16),
                  Text('正在读取本机学习数据…'),
                ],
              ),
            ),
            error: (error, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(error is StateError ? error.message : '今日概览读取失败，请重试。'),
                const SizedBox(height: 16),
                PressableAction(
                  label: '重新读取今日概览',
                  onPressed: () => ref.invalidate(homeSummaryProvider),
                ),
              ],
            ),
            data: (snapshot) {
              _scheduleRefresh(snapshot);
              final availability = snapshot.availability;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (availability.totalCards == 0) ...[
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: Icon(
                                Icons.style_outlined,
                                size: 40,
                                color: scheme.primary,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              '先放入你的第一张卡片',
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            const SizedBox(height: 12),
                            const Text('导入文字、图片牌组，或自己新建卡片。学习进度只保存在本机。'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    PressableAction(
                      label: '导入 .apkg 牌组',
                      onPressed: () => context.push('/import'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(48, 48),
                      ),
                      onPressed: _creatingCard
                          ? null
                          : () {
                              unawaited(FeedbackScope.of(context).tap());
                              unawaited(_createCard(snapshot));
                            },
                      child: const Text('新建第一张卡片'),
                    ),
                  ] else ...[
                    TodayOverview(summary: snapshot),
                    const SizedBox(height: 20),
                    PressableAction(
                      label: availability.availableCards > 0
                          ? '开始今日学习'
                          : '暂时没有可学卡片',
                      onPressed: availability.availableCards == 0
                          ? null
                          : () async {
                              await context.push('/study');
                              if (mounted) ref.invalidate(homeSummaryProvider);
                            },
                    ),
                    const SizedBox(height: 8),
                    if (availability.availableCards == 0)
                      TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () => _go('/study-settings'),
                        child: const Text('调整学习设置'),
                      ),
                    const SizedBox(height: 16),
                    Card(
                      margin: EdgeInsets.zero,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '今日已学 ${snapshot.studiedCards} 张',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '已评分 ${snapshot.ratingCount} 次 · 当前连续 ${snapshot.streak} 天',
                            ),
                            const SizedBox(height: 8),
                            TextButton(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                              ),
                              onPressed: () => _go('/records', replace: true),
                              child: const Text('查看学习记录'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 32),
                  Text('本机知识库', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(
                    '${availability.totalCards} 张卡片 · ${snapshot.deckCount} 个牌组（含章节）',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  if (snapshot.decks.isNotEmpty)
                    Card(
                      margin: EdgeInsets.zero,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (final deck in snapshot.decks)
                            InkWell(
                              onTap: () => _go('/decks/${deck.id}'),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(
                                  children: [
                                    ExcludeSemantics(
                                      child: Icon(
                                        Icons.layers_outlined,
                                        color: scheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            deck.name,
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${deck.cardCount} 张卡片 · 含子章节',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const ExcludeSemantics(
                                      child: Icon(Icons.chevron_right),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => _go('/decks', replace: true),
                    child: const Text('查看全部牌组'),
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
