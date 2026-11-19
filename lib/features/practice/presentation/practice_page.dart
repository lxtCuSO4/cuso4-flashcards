import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/media/local_audio_controller.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/touhou_tag.dart';
import '../../../core/widgets/pressable_action.dart';
import '../../study/domain/study_card.dart';
import '../../decks/domain/choice_question.dart';
import '../../decks/domain/choice_attempt.dart';
import '../data/practice_repository.dart';
import '../data/practice_session_repository.dart';
import 'practice_card_face.dart';
import 'choice_explanation_page.dart';
import 'choice_practice_scaffold.dart';
import 'practice_answer_sheet.dart';
import '../../../app/theme/lunar_theme.dart';

class PracticePage extends ConsumerStatefulWidget {
  const PracticePage({
    super.key,
    this.deckId,
    this.favoritesOnly = false,
    this.includeChildren = true,
    this.choicesOnly = false,
    this.wrongOnly = false,
  });
  final int? deckId;
  final bool favoritesOnly;
  final bool includeChildren;
  final bool choicesOnly;
  final bool wrongOnly;
  @override
  ConsumerState<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends ConsumerState<PracticePage>
    with WidgetsBindingObserver {
  final _scroll = ScrollController();
  late final LocalAudioController _audio;
  late final PracticeSessionRepository _sessions;
  PracticeSession? _session;
  PracticeSession? _resume;
  final _answerClock = Stopwatch();
  int _elapsedBase = 0;
  int get _elapsed => _elapsedBase + _answerClock.elapsedMilliseconds;
  late bool _includeChildren;
  bool _busy = true;
  bool _answerVisible = false;
  bool get _completed => _session?.completed ?? false;
  String? _error;
  PracticeRound? get _round => _session?.round;
  StudyCard? _card;
  int get _index => _session?.index ?? 0;
  int get _skipped => _session?.skipped ?? 0;
  int get _correct => _session?.correct ?? 0;
  int get _incorrect => _session?.incorrect ?? 0;
  int get _unanswered => _session?.unanswered ?? 0;
  bool _explanationOpen = false;
  late PracticeOrder _order;

  bool get _choiceMode => widget.choicesOnly || widget.wrongOnly;
  String get _title => widget.wrongOnly
      ? '错题练习'
      : widget.favoritesOnly && _choiceMode
      ? '收藏选择题练习'
      : _choiceMode
      ? '选择题练习'
      : widget.favoritesOnly
      ? '收藏${_order == PracticeOrder.random ? '随机' : '顺序'}练习'
      : '${_order == PracticeOrder.random ? '随机' : '顺序'}练习';

  @override
  void initState() {
    super.initState();
    _includeChildren = widget.includeChildren;
    _order = _choiceMode ? PracticeOrder.sequential : PracticeOrder.random;
    WidgetsBinding.instance.addObserver(this);
    _audio = LocalAudioController(ref.read(mediaRepositoryProvider));
    _sessions = PracticeSessionRepository(ref.read(practiceRepositoryProvider));
    unawaited(_prepareEntry());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(_audio.stop());
      _pauseClock();
    } else if (!_busy &&
        _session?.isChoice == true &&
        !_answerVisible &&
        ModalRoute.of(context)?.isCurrent == true) {
      _answerClock.start();
    }
  }

  @override
  void dispose() {
    _pauseClock();
    WidgetsBinding.instance.removeObserver(this);
    _audio.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _top() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  PracticeScope get _scope => PracticeScope(
    deckId: widget.deckId,
    includeChildren: _includeChildren,
    favoritesOnly: widget.favoritesOnly,
    choicesOnly: _choiceMode,
    wrongOnly: widget.wrongOnly,
    order: _order,
  );

  void _adopt(PracticeSession session) {
    _session = session;
    _answerVisible = session.answerVisible;
  }

  Future<void> _prepareEntry({bool preferences = true}) async {
    setState(() {
      _busy = true;
      _error = null;
      _resume = null;
    });
    try {
      if (preferences) {
        final saved = await _sessions.preferences(
          _scope,
          entryChildren: widget.includeChildren,
        );
        if (!mounted) return;
        _includeChildren = saved.includeChildren;
        _order = saved.order;
      }
      final saved = await _sessions.peek(_scope);
      if (mounted && saved?.round.cardIds.isNotEmpty == true) _resume = saved;
    } catch (error) {
      if (mounted) {
        _error = error is StateError ? error.message : '练习进度读取失败，请重试。';
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _changeScope({PracticeOrder? order, bool? children}) async {
    if (_busy) return;
    setState(() {
      _order = order ?? _order;
      _includeChildren = children ?? _includeChildren;
    });
    await _prepareEntry(preferences: false);
  }

  String get _emptyMessage => widget.wrongOnly
      ? '当前范围没有错题，答错的选择题会自动加入。'
      : _choiceMode
      ? '当前范围没有${widget.favoritesOnly ? '收藏的' : ''}选择题。可调整范围，或添加、导入选择题。'
      : widget.favoritesOnly
      ? '当前范围没有收藏卡片。可调整章节范围，或先收藏卡片。'
      : '当前范围没有卡片。可包含子章节，或先添加、导入卡片。';

  Future<void> _start({bool restart = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _sessions.remember(_scope, entryChildren: widget.includeChildren);
      final session = await _sessions.open(_scope, restart: restart);
      if (!mounted) return;
      if (session.round.cardIds.isEmpty) {
        setState(() {
          _session = null;
          _card = null;
          _resume = null;
          _error = _emptyMessage;
          _busy = false;
        });
        return;
      }
      _adopt(session);
      if (session.completed) {
        setState(() {
          _card = null;
          _busy = false;
        });
      } else {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is StateError ? error.message : '准备练习失败，请重试。';
        });
      }
    }
  }

  Future<void> _restart() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('从头练习？'),
        content: const Text('仅重置当前范围和练习方式的进度。错题、收藏和记忆排程保持不变。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('继续原进度'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('重新开始'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _start(restart: true);
  }

  Future<void> _load() async {
    _answerClock.stop();
    setState(() {
      _busy = true;
      _card = null;
      _error = null;
    });
    _top();
    try {
      await _audio.stop();
      while (mounted && !_session!.completed) {
        StudyCard item;
        try {
          item = await ref
              .read(studyRepositoryProvider)
              .getStudyCard(_session!.cardId!);
        } on StateError catch (error) {
          if (error.message != '卡片不存在') rethrow;
          _adopt(await _sessions.advance(_session!, skip: true));
          continue;
        }
        if (!mounted) return;
        // A graded wrong-list card may already have left that list. Keep its
        // explanation; only pending cards are rechecked against the scope.
        if (!_session!.answerVisible &&
            !await ref
                .read(practiceRepositoryProvider)
                .isEligible(_session!.scope, item.card.id)) {
          _adopt(await _sessions.advance(_session!, skip: true));
          continue;
        }
        final choice = item.note.type.isChoice
            ? ChoiceQuestion.fromFields(item.note.type, item.note.fields)
            : null;
        final signature = jsonEncode({
          'type': item.note.type.index,
          'fields': choice?.toFields() ?? item.note.fields,
        });
        final session = await _sessions.bindQuestion(
          _session!,
          signature: signature,
          isChoice: choice != null,
          optionCount: choice?.options.length ?? 0,
          shuffle: choice?.shuffle ?? false,
        );
        if (!mounted) return;
        setState(() {
          _adopt(session);
          _card = item;
          _busy = false;
        });
        _elapsedBase = session.elapsedMs;
        _answerClock.reset();
        if (choice != null && !session.answerVisible) _answerClock.start();
        if (session.explanation && session.attempt != null) {
          unawaited(_openExplanation(session.attempt!));
        }
        return;
      }
      if (mounted) setState(() => _busy = false);
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error is StateError ? error.message : '卡片暂时无法加载，请重试。';
        });
      }
    }
  }

  Future<void> _next({bool skip = false}) async {
    if (_busy || (!skip && !_answerVisible) || _session == null) return;
    setState(() => _busy = true);
    try {
      await _audio.stop();
      final next = await _sessions.advance(_session!, skip: skip);
      if (!mounted) return;
      _adopt(next);
      if (next.completed) {
        setState(() {
          _card = null;
          _busy = false;
          _error = null;
        });
        _top();
      } else {
        await _load();
      }
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showActionError(context, error);
      }
    }
  }

  Future<void> _recordAttempt(ChoiceAttemptSnapshot attempt) async {
    if (_busy || _session == null) throw StateError('请等待当前操作完成。');
    setState(() => _busy = true);
    try {
      final saved = await _sessions.saveAttempt(
        _session!,
        attempt,
        elapsedMs: _elapsed,
      );
      if (mounted) _adopt(saved);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revealAnswer() async {
    if (_busy || _session == null) return;
    setState(() => _busy = true);
    try {
      final saved = await _sessions.reveal(_session!);
      if (mounted) _adopt(saved);
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _submitChoice(Set<int> selected) async {
    if (_busy || _card == null || _session == null) {
      throw StateError('请等待当前操作完成。');
    }
    setState(() => _busy = true);
    _answerClock.stop();
    try {
      final saved = await _sessions.submit(
        _session!,
        selected,
        elapsedMs: _elapsed,
        sourceDeckName: _card!.deckName,
        question: ChoiceQuestion.fromFields(
          _card!.note.type,
          _card!.note.fields,
        ),
      );
      if (mounted) _adopt(saved);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openExplanation(ChoiceAttemptSnapshot attempt) async {
    final item = _card;
    if (_busy || _explanationOpen || item == null || !item.note.type.isChoice) {
      return;
    }
    _explanationOpen = true;
    _answerClock.stop();
    setState(() => _busy = true);
    try {
      await _audio.stop();
      if (!mounted) return;
      final saved = await _sessions.reveal(_session!, explanation: true);
      if (!mounted) return;
      setState(() {
        _adopt(saved);
        _busy = false;
      });
      int? jumpTarget;
      final advance = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'choice-explanation'),
          builder: (_) => ChoiceExplanationPage(
            question: ChoiceQuestion.fromFields(
              item.note.type,
              item.note.fields,
            ),
            attempt: saved.attempt ?? attempt,
            media: ref.read(mediaRepositoryProvider),
            deckName: item.deckName,
            position: _index + 1,
            total: _round!.cardIds.length,
            onAnswerSheet: () async {
              jumpTarget = await _chooseQuestion();
              return jumpTarget;
            },
          ),
        ),
      );
      if (!mounted ||
          _card?.card.id != item.card.id ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      setState(() => _busy = true);
      _adopt(await _sessions.explanation(_session!, false));
      if (!mounted) return;
      setState(() => _busy = false);
      if (jumpTarget != null) {
        await _jump(jumpTarget!);
      } else if (advance == true) {
        await _next();
      }
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      _explanationOpen = false;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _favorite() async {
    final item = _card;
    if (_busy || item == null) return;
    setState(() => _busy = true);
    unawaited(FeedbackScope.of(context).tap());
    try {
      await ref
          .read(studyRepositoryProvider)
          .setFavorite(item.card.id, !item.card.isFavorite);
      final updated = await ref
          .read(studyRepositoryProvider)
          .getStudyCard(item.card.id);
      if (mounted) setState(() => _card = updated);
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final item = _card;
    if (_busy || item == null) return;
    setState(() => _busy = true);
    await _audio.stop();
    if (!mounted) return;
    try {
      _answerClock.stop();
      if (_session != null && !_answerVisible) {
        await _sessions.saveElapsed(_session!, _elapsed);
      }
      if (!mounted) return;
      await context.push('/decks/${item.note.deckId}/edit/${item.note.id}');
    } finally {
      if (mounted) await _load();
    }
  }

  void _configure() {
    _pauseClock();
    unawaited(_audio.stop());
    setState(() {
      _session = null;
      _card = null;
      _error = null;
      _answerVisible = false;
    });
    _top();
    unawaited(_prepareEntry(preferences: false));
  }

  void _pauseClock() {
    _answerClock.stop();
    final session = _session;
    if (session != null &&
        session.isChoice &&
        !session.answerVisible &&
        !session.completed) {
      unawaited(_sessions.saveElapsed(session, _elapsed).catchError((_) {}));
    }
  }

  Future<int?> _chooseQuestion() async {
    if (_busy || _session == null) return null;
    unawaited(FeedbackScope.of(context).tap());
    _answerClock.stop();
    setState(() => _busy = true);
    try {
      if (!_answerVisible && !_completed) {
        await _sessions.saveElapsed(_session!, _elapsed);
      }
      if (!mounted) return null;
      // The modal blocks input itself; avoid an endless loading animation on
      // the completed-round page while the answer sheet is open.
      setState(() => _busy = false);
      return await showModalBottomSheet<int>(
        context: context,
        backgroundColor: LunarPalette.of(context).paper,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => LunarSurface(
          child: PracticeAnswerSheet(session: _session!, repository: _sessions),
        ),
      );
    } catch (error) {
      if (mounted) showActionError(context, error);
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _answerSheet() async {
    final target = await _chooseQuestion();
    if (!mounted) return;
    if (target != null) {
      await _jump(target);
    } else if (!_answerVisible && _session?.isChoice == true) {
      _answerClock.start();
    }
  }

  Future<void> _jump(int target) async {
    if (_busy || _session == null) return;
    _answerClock.stop();
    setState(() => _busy = true);
    try {
      if (!_answerVisible && !_completed) {
        await _sessions.saveElapsed(_session!, _elapsed);
      }
      _adopt(await _sessions.jump(_session!, target));
      if (mounted) await _load();
    } catch (error) {
      if (mounted) {
        setState(() => _busy = false);
        showActionError(context, error);
      }
    }
  }

  Future<void> _showSummary() async {
    if (_busy || _session == null) return;
    setState(() => _busy = true);
    try {
      _adopt(await _sessions.showSummary(_session!));
      if (mounted) setState(() => _card = null);
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final round = _round;
    final current = _card;
    if (round != null &&
        !_completed &&
        current != null &&
        current.note.type.isChoice) {
      return PopScope(
        canPop: !_busy,
        child: ChoicePracticeScaffold(
          title: _title,
          item: current,
          media: ref.read(mediaRepositoryProvider),
          audio: _audio,
          answerVisible: _answerVisible,
          busy: _busy,
          position: _index + 1,
          total: round.cardIds.length,
          place: widget.favoritesOnly
              ? TouhouPlace.bookmarks
              : TouhouPlace.bamboo,
          onReveal: () => setState(() => _answerVisible = true),
          onSubmit: _submitChoice,
          onReview: (attempt) => unawaited(_openExplanation(attempt)),
          onNext: _next,
          nextLabel: _index + 1 == round.cardIds.length ? '完成本轮' : '下一张',
          onFavorite: _favorite,
          onEdit: _edit,
          onSkip: () => _next(skip: true),
          onConfigure: _configure,
          onAnswerSheet: () => unawaited(_answerSheet()),
          onPrevious: _index > 0 ? () => unawaited(_jump(_index - 1)) : null,
          onSummary: _session!.roundFinished
              ? () => unawaited(_showSummary())
              : null,
          notice: _session!.legacyReview ? '旧版未保存本题答案，仅供回看；新开一轮可重新作答' : null,
          initialAttempt: _session?.attempt,
          onAttemptChanged: _recordAttempt,
        ),
      );
    }
    final deckName =
        round?.deckName ??
        (widget.deckId == null ? '全部牌组' : null) ??
        ref
            .watch(decksProvider)
            .value
            ?.where((d) => d.id == widget.deckId)
            .firstOrNull
            ?.name ??
        '当前牌组';
    return PopScope(
      canPop: !_busy,
      child: PageFrame(
        exterior: round == null || _completed,
        title: _title,
        header: TouhouTag(
          widget.favoritesOnly ? TouhouPlace.bookmarks : TouhouPlace.bamboo,
        ),
        subtitle: '独立练习，不参与记忆排程；选择题答错记入错题，答对自动移出',
        scrollController: _scroll,
        actions: [
          if (round != null)
            IconButton(
              tooltip: '本轮答题卡',
              icon: const Icon(Icons.grid_view_outlined),
              onPressed: _busy ? null : () => unawaited(_answerSheet()),
            ),
          if (round != null && !_completed)
            IconButton(
              tooltip: '切换练习方式',
              onPressed: _busy ? null : _configure,
              icon: const Icon(Icons.tune),
            ),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(deckName, style: Theme.of(context).textTheme.titleLarge),
            if (widget.favoritesOnly) ...[
              const SizedBox(height: 8),
              const Text('仅练习收藏卡片'),
            ],
            const SizedBox(height: 24),
            if (round == null) ...[
              Text(
                _choiceMode
                    ? '单选、多选独立刷题。提交后判分；直接看答案或跳过不会改变错题列表。'
                    : '随时抽卡，自由巩固。包含未学、已学和未到期卡片，同一轮不重复。',
              ),
              const SizedBox(height: 16),
              SegmentedButton<PracticeOrder>(
                segments: const [
                  ButtonSegment(
                    value: PracticeOrder.sequential,
                    label: Text('顺序练习'),
                    icon: Icon(Icons.format_list_numbered),
                  ),
                  ButtonSegment(
                    value: PracticeOrder.random,
                    label: Text('随机练习'),
                    icon: Icon(Icons.shuffle),
                  ),
                ],
                selected: {_order},
                onSelectionChanged: _busy
                    ? null
                    : (value) {
                        unawaited(FeedbackScope.of(context).tap());
                        unawaited(_changeScope(order: value.single));
                      },
              ),
              const SizedBox(height: 24),
              const Text('按当前范围练习全部卡片，同一轮不重复，进度自动保存。'),
              const SizedBox(height: 16),
              if (widget.deckId != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('包含子章节'),
                  subtitle: const Text('同时抽取这个牌组下各级章节的卡片'),
                  value: _includeChildren,
                  onChanged: _busy
                      ? null
                      : (value) {
                          unawaited(FeedbackScope.of(context).tap());
                          unawaited(_changeScope(children: value));
                        },
                ),
              const SizedBox(height: 24),
              PressableAction(
                label: _resume == null
                    ? (_order == PracticeOrder.random ? '开始随机练习' : '开始顺序练习')
                    : _resume!.completed
                    ? '查看本轮结果'
                    : (_order == PracticeOrder.random ? '继续随机练习' : '继续顺序练习'),
                onPressed: _busy ? null : _start,
              ),
              if (_resume != null) ...[
                const SizedBox(height: 12),
                Text(
                  _resume!.completed
                      ? '本轮已完成'
                      : '上次停在第 ${_resume!.index + 1} / ${_resume!.round.cardIds.length} 张，已自动保存',
                ),
              ],
              if (_resume != null || _error != null)
                TextButton(
                  onPressed: _busy ? null : _restart,
                  child: const Text('从头练习'),
                ),
            ] else if (_completed) ...[
              Text('本轮练习完成', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              Text('已练习 ${round.cardIds.length - _skipped} 张'),
              if (_skipped > 0) Text('另有 $_skipped 张已跳过'),
              if (_correct + _incorrect + _unanswered > 0)
                Text('答对 $_correct 题 · 答错 $_incorrect 题 · 未作答 $_unanswered 题'),
              const SizedBox(height: 16),
              const Text('不改变记忆排程。选择题提交单独计入刷题记录；答错加入错题，答对自动移出。'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _answerSheet,
                icon: const Icon(Icons.grid_view_outlined),
                label: const Text('查看本轮答题卡'),
              ),
              const SizedBox(height: 24),
              PressableAction(
                label: '再练一轮',
                onPressed: _busy ? null : () => _start(restart: true),
              ),
              const SizedBox(height: 12),
              PressableAction(
                label: '调整练习设置',
                onPressed: _busy ? null : _configure,
              ),
            ] else ...[
              Semantics(
                liveRegion: true,
                child: Text('第 ${_index + 1} / ${round.cardIds.length} 张'),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: _index / round.cardIds.length),
              const SizedBox(height: 24),
              if (_card case final item?) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: item.card.isFavorite ? '取消收藏' : '收藏卡片',
                      onPressed: _busy ? null : _favorite,
                      icon: Icon(
                        item.card.isFavorite
                            ? Icons.bookmark
                            : Icons.bookmark_border,
                      ),
                    ),
                    IconButton(
                      tooltip: '编辑卡片',
                      onPressed: _busy ? null : _edit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ),
                PracticeCardFace(
                  key: ValueKey('practice-card-${item.card.id}'),
                  item: item,
                  answerVisible: _answerVisible,
                  media: ref.read(mediaRepositoryProvider),
                  audio: _audio,
                  onReveal: _busy
                      ? null
                      : () => setState(() => _answerVisible = true),
                  onSubmit: _submitChoice,
                  onReview: (attempt) => unawaited(_openExplanation(attempt)),
                  initialAttempt: _session?.attempt,
                  onAttemptChanged: _recordAttempt,
                ),
                const SizedBox(height: 24),
                if (!_answerVisible && !item.note.type.isChoice)
                  PressableAction(
                    label: '显示答案',
                    onPressed: _busy ? null : () => unawaited(_revealAnswer()),
                  ),
                if (_answerVisible)
                  PressableAction(
                    label: _index + 1 == round.cardIds.length ? '完成本轮' : '下一张',
                    onPressed: _busy ? null : _next,
                  ),
                if (!_answerVisible)
                  TextButton(
                    onPressed: _busy ? null : () => _next(skip: true),
                    child: const Text('跳过此题'),
                  ),
              ],
            ],
            if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text('正在准备卡片…'),
            ],
            if (_error case final error?) ...[
              const SizedBox(height: 16),
              Semantics(
                liveRegion: true,
                child: Text(
                  error,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
              if (round != null && !_completed) ...[
                const SizedBox(height: 16),
                PressableAction(label: '重试加载', onPressed: _busy ? null : _load),
                const SizedBox(height: 12),
                PressableAction(
                  label: '跳过此卡',
                  onPressed: _busy ? null : () => _next(skip: true),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
