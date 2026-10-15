import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/content/card_content.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/media/local_audio_controller.dart';
import '../../../core/widgets/pressable_action.dart';
import '../../../core/widgets/touhou_tag.dart';
import '../../decks/domain/cloze_parser.dart';
import '../../decks/domain/note.dart';
import '../application/study_session_controller.dart';
import '../domain/scheduler.dart';
import 'review_rating_bar.dart';

class StudyPage extends ConsumerStatefulWidget {
  const StudyPage({super.key, this.deckId});
  final int? deckId;
  @override
  ConsumerState<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends ConsumerState<StudyPage>
    with WidgetsBindingObserver {
  late final StudySessionController _session;
  late final LocalAudioController _audio;
  final _scroll = ScrollController();
  bool _editing = false;
  bool get _locked => _session.busy || _editing;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _session = StudySessionController(
      ref.read(studyRepositoryProvider),
      deckId: widget.deckId,
      loadSettings: ref.read(studySettingsRepositoryProvider).load,
    );
    _audio = LocalAudioController(ref.read(mediaRepositoryProvider));
    unawaited(_session.start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_audio.stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audio.dispose();
    _session.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _resetScroll() {
    if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _rate(ReviewRating rating) async {
    if (_locked) return;
    unawaited(_audio.stop());
    await _session.rate(rating);
    _resetScroll();
  }

  Future<void> _undo() async {
    if (_locked) return;
    unawaited(_audio.stop());
    await _session.undo();
    _resetScroll();
  }

  Future<void> _reload() async {
    if (_locked) return;
    unawaited(_audio.stop());
    await _session.start();
    _resetScroll();
  }

  Future<void> _edit() async {
    final note = _session.current?.note;
    if (_locked || note == null) return;
    setState(() => _editing = true);
    unawaited(_audio.stop());
    try {
      await context.push('/decks/${note.deckId}/edit/${note.id}');
      if (mounted) await _session.start();
    } finally {
      if (mounted) {
        setState(() => _editing = false);
        _resetScroll();
      }
    }
  }

  void _exit() {
    if (_locked) return;
    unawaited(FeedbackScope.of(context).tap());
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: AppTheme.dark,
    child: ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final item = _session.current;
        final note = item?.note;
        final parser = ClozeParser();
        final question = note == null
            ? ''
            : note.type == NoteType.basic
            ? note.fields['front'] ?? ''
            : parser.renderQuestion(
                note.fields['text'] ?? '',
                item!.card.clozeIndex!,
              );
        final answer = note == null
            ? ''
            : note.type == NoteType.basic
            ? note.fields['back'] ?? ''
            : parser.renderAnswer(
                note.fields['text'] ?? '',
                item!.card.clozeIndex!,
              );
        Widget content(String source) => CardContent(
          source: source,
          media: ref.read(mediaRepositoryProvider),
          audio: _audio,
        );
        return PopScope(
          canPop: !_locked,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              leading: IconButton(
                tooltip: '退出学习',
                onPressed: _locked ? null : _exit,
                icon: const Icon(Icons.close),
              ),
              title: const Text('专注学习'),
            ),
            body: SafeArea(
              top: false,
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  controller: _scroll,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 760,
                        minHeight: box.maxHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const TouhouTag(
                                  TouhouPlace.study,
                                  margin: EdgeInsets.only(bottom: 12),
                                ),
                                Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    Text(
                                      '本轮已学 ${_session.completedReviews} 次',
                                      style: TextStyle(color: scheme.primary),
                                    ),
                                    Wrap(
                                      children: [
                                        IconButton(
                                          tooltip: '撤销上次评分',
                                          onPressed:
                                              !_locked && _session.canUndo
                                              ? () {
                                                  unawaited(
                                                    FeedbackScope.of(context)
                                                        .tap(),
                                                  );
                                                  unawaited(_undo());
                                                }
                                              : null,
                                          icon: const Icon(Icons.undo_rounded),
                                        ),
                                        IconButton(
                                          tooltip: item?.card.isFavorite == true
                                              ? '取消收藏'
                                              : '收藏卡片',
                                          onPressed: !_locked && item != null
                                              ? () {
                                                  unawaited(
                                                    FeedbackScope.of(context)
                                                        .tap(),
                                                  );
                                                  unawaited(
                                                    _session.toggleFavorite(),
                                                  );
                                                }
                                              : null,
                                          icon: Icon(
                                            item?.card.isFavorite == true
                                                ? Icons.bookmark
                                                : Icons.bookmark_border,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: '编辑卡片',
                                          onPressed: !_locked && item != null
                                              ? () {
                                                  unawaited(
                                                    FeedbackScope.of(context)
                                                        .tap(),
                                                  );
                                                  unawaited(_edit());
                                                }
                                              : null,
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                if (_session.busy)
                                  const LinearProgressIndicator(),
                                if (item != null)
                                  Container(
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                      color: scheme.surface,
                                      borderRadius: BorderRadius.circular(28),
                                      border: Border.all(
                                        color: scheme.primary.withValues(
                                          alpha: .16,
                                        ),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          item.deckName,
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(color: scheme.primary),
                                        ),
                                        const SizedBox(height: 24),
                                        Text(
                                          '先在心里回想',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium,
                                        ),
                                        const SizedBox(height: 12),
                                        content(question),
                                        if (_session.answerVisible) ...[
                                          const Padding(
                                            padding: EdgeInsets.symmetric(
                                              vertical: 20,
                                            ),
                                            child: Divider(),
                                          ),
                                          Semantics(
                                            liveRegion: true,
                                            child: Text(
                                              '答案',
                                              style: TextStyle(
                                                color: scheme.primary,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          content(
                                            answer.isEmpty ? '（空白答案）' : answer,
                                          ),
                                          if (note!.type == NoteType.cloze &&
                                              (note.fields['extra'] ?? '')
                                                  .isNotEmpty) ...[
                                            const SizedBox(height: 16),
                                            content(note.fields['extra']!),
                                          ],
                                        ],
                                      ],
                                    ),
                                  ),
                                if (_session.isComplete)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 48,
                                    ),
                                    child: Column(
                                      children: [
                                        Icon(
                                          Icons.check_circle_outline,
                                          color: scheme.primary,
                                          size: 52,
                                        ),
                                        const SizedBox(height: 24),
                                        Text(
                                          '当前没有可学习卡片',
                                          style: Theme.of(context)
                                              .textTheme
                                              .headlineSmall,
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 12),
                                        const Text(
                                          '到期卡片已学完，或已达到今日额度。\n学习步骤到期后，可以重新载入。',
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  ),
                                if (_session.error != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                    ),
                                    child: Semantics(
                                      liveRegion: true,
                                      child: Text(
                                        _session.error!,
                                        style: TextStyle(color: scheme.error),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 32),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (item != null && !_session.answerVisible)
                                    PressableAction(
                                      label: '显示答案',
                                      onPressed: _locked
                                          ? null
                                          : _session.showAnswer,
                                    ),
                                  if (item != null &&
                                      _session.answerVisible) ...[
                                    const Text(
                                      '按实际回忆情况评分',
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    ReviewRatingBar(
                                      intervals: _session.previewIntervals,
                                      onRate: _locked ? null : _rate,
                                    ),
                                  ],
                                  if (item == null && !_session.busy)
                                    PressableAction(
                                      label: '重新载入',
                                      onPressed: _locked ? null : _reload,
                                    ),
                                  if (item != null && _session.error != null)
                                    TextButton(
                                      onPressed: _locked ? null : _reload,
                                      child: const Text('重新载入当前队列'),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}
