import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/media/local_audio_controller.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/touhou_tag.dart';
import '../../../core/widgets/pressable_action.dart';
import '../../study/domain/study_card.dart';
import '../data/practice_repository.dart';
import 'practice_card_face.dart';

class PracticePage extends ConsumerStatefulWidget {
  const PracticePage({
    super.key,
    this.deckId,
    this.favoritesOnly = false,
    this.includeChildren = true,
  });
  final int? deckId;
  final bool favoritesOnly;
  final bool includeChildren;
  @override
  ConsumerState<PracticePage> createState() => _PracticePageState();
}

class _PracticePageState extends ConsumerState<PracticePage>
    with WidgetsBindingObserver {
  final _form = GlobalKey<FormState>();
  final _count = TextEditingController(text: '20');
  final _scroll = ScrollController();
  late final LocalAudioController _audio;
  late bool _includeChildren;
  bool _busy = false;
  bool _answerVisible = false;
  bool _completed = false;
  String? _error;
  PracticeRound? _round;
  StudyCard? _card;
  int _index = 0;
  int _skipped = 0;

  @override
  void initState() {
    super.initState();
    _includeChildren = widget.includeChildren;
    WidgetsBinding.instance.addObserver(this);
    _audio = LocalAudioController(ref.read(mediaRepositoryProvider));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_audio.stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audio.dispose();
    _scroll.dispose();
    _count.dispose();
    super.dispose();
  }

  void _top() {
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _start() async {
    if (_busy || !(_form.currentState?.validate() ?? true)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final round = await ref
          .read(practiceRepositoryProvider)
          .sample(
            deckId: widget.deckId,
            includeChildren: _includeChildren,
            count: int.parse(_count.text.trim()),
            favoritesOnly: widget.favoritesOnly,
          );
      if (!mounted) return;
      if (round.cardIds.isEmpty) {
        setState(() {
          _busy = false;
          _round = null;
          _card = null;
          _completed = false;
          _error = widget.favoritesOnly
              ? '当前范围没有收藏卡片。可调整章节范围，或先收藏卡片。'
              : '当前范围没有卡片。可包含子章节，或先添加、导入卡片。';
        });
        return;
      }
      setState(() {
        _round = round;
        _index = 0;
        _skipped = 0;
        _completed = false;
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e is StateError ? e.message : '抽卡失败，请重试。';
      });
    }
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _answerVisible = false;
      _card = null;
      _error = null;
    });
    _top();
    try {
      await _audio.stop();
      if (!mounted) return;
      final card = await ref
          .read(studyRepositoryProvider)
          .getStudyCard(_round!.cardIds[_index]);
      if (!mounted) return;
      setState(() {
        _card = card;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '卡片已删除或暂时无法加载。可以重试，或跳过这张卡片。';
      });
    }
  }

  Future<void> _next({bool skip = false}) async {
    if (_busy || (!skip && !_answerVisible)) return;
    setState(() {
      _busy = true;
    });
    await _audio.stop();
    if (!mounted) return;
    if (skip) _skipped++;
    if (_index + 1 == _round!.cardIds.length) {
      setState(() {
        _completed = true;
        _busy = false;
        _error = null;
        _card = null;
      });
      _top();
      return;
    }
    _index++;
    await _load();
  }

  void _configure() {
    unawaited(_audio.stop());
    setState(() {
      _round = null;
      _card = null;
      _error = null;
      _completed = false;
      _answerVisible = false;
    });
    _top();
  }

  @override
  Widget build(BuildContext context) {
    final round = _round;
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
    return PageFrame(
      title: widget.favoritesOnly ? '收藏随机练习' : '随机练习',
      header: TouhouTag(
        widget.favoritesOnly ? TouhouPlace.bookmarks : TouhouPlace.bamboo,
      ),
      subtitle: '不改变 FSRS 进度、每日额度和学习统计',
      scrollController: _scroll,
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
            const Text('随时抽卡，自由巩固。包含未学、已学和未到期卡片，同一轮不重复。'),
            const SizedBox(height: 24),
            Form(
              key: _form,
              child: TextFormField(
                controller: _count,
                enabled: !_busy,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(3),
                ],
                decoration: const InputDecoration(
                  labelText: '练习张数',
                  helperText: '1–500 张；数量不足时使用全部卡片',
                  helperMaxLines: 3,
                  errorMaxLines: 3,
                ),
                validator: (value) {
                  final number = int.tryParse(value?.trim() ?? '');
                  return number == null ||
                          number < 1 ||
                          number > PracticeRepository.maxCount
                      ? '请输入 1–500 之间的整数'
                      : null;
                },
              ),
            ),
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
                        setState(() {
                          _includeChildren = value;
                          _error = null;
                        });
                      },
              ),
            const SizedBox(height: 24),
            PressableAction(label: '开始随机练习', onPressed: _busy ? null : _start),
          ] else if (_completed) ...[
            Text('本轮练习完成', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Text('已练习 ${round.cardIds.length - _skipped} 张'),
            if (_skipped > 0) Text('另有 $_skipped 张未能加载，已跳过'),
            const SizedBox(height: 16),
            const Text('本轮未写入学习记录。下一轮重新随机抽取，可能遇到本轮的卡片。'),
            const SizedBox(height: 24),
            PressableAction(label: '再练一轮', onPressed: _busy ? null : _start),
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
              PracticeCardFace(
                key: ValueKey('practice-card-${item.card.id}'),
                item: item,
                answerVisible: _answerVisible,
                media: ref.read(mediaRepositoryProvider),
                audio: _audio,
                onReveal: () => setState(() => _answerVisible = true),
              ),
              const SizedBox(height: 24),
              if (!_answerVisible && !item.note.type.isChoice)
                PressableAction(
                  label: '显示答案',
                  onPressed: _busy
                      ? null
                      : () => setState(() => _answerVisible = true),
                ),
              if (_answerVisible)
                PressableAction(
                  label: _index + 1 == round.cardIds.length ? '完成本轮' : '下一张',
                  onPressed: _busy ? null : _next,
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
    );
  }
}
