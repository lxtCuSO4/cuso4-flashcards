import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/content/card_content.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/media/local_audio_controller.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';
import '../../../core/widgets/touhou_tag.dart';
import '../../decks/domain/cloze_parser.dart';
import '../../decks/domain/choice_question.dart';
import '../../decks/domain/note.dart';
import '../../decks/presentation/choice_card_face.dart';
import '../../study/domain/study_card.dart';
import '../data/recitation_repository.dart';

class RecitationPage extends ConsumerStatefulWidget {
  const RecitationPage({super.key, required this.deckId});
  final int deckId;
  @override
  ConsumerState<RecitationPage> createState() => _RecitationPageState();
}

class _RecitationPageState extends ConsumerState<RecitationPage>
    with WidgetsBindingObserver {
  late final _repository = RecitationRepository(ref.read(databaseProvider));
  late final _audio = LocalAudioController(ref.read(mediaRepositoryProvider));
  final _scroll = ScrollController();
  RecitationRound? _round;
  StudyCard? _item;
  int _index = 0;
  bool _busy = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_open());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_audio.stop());
  }

  Future<void> _open({bool? children, bool? random}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final round = await _repository.open(
        widget.deckId,
        includeChildren: children,
        random: random,
      );
      if (!mounted) return;
      if (round.noteIds.isEmpty) {
        await _audio.stop();
        await _repository.savePosition(widget.deckId, round, 0);
        if (!mounted) return;
        setState(() {
          _round = round;
          _item = null;
          _index = 0;
        });
      } else {
        await _load(round, round.index);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is StateError ? error.message : '背卡内容读取失败，请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load(RecitationRound round, int index) async {
    await _audio.stop();
    final item = await ref
        .read(studyRepositoryProvider)
        .getStudyCard(round.cardIds[index]);
    if (!mounted) return;
    await _repository.savePosition(widget.deckId, round, index);
    if (!mounted) return;
    setState(() {
      _round = round;
      _index = index;
      _item = item;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _move(int delta) async {
    final round = _round;
    if (_busy || round == null) return;
    final next = _index + delta;
    if (next < 0 || next >= round.noteIds.length) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _load(round, next);
    } catch (_) {
      if (mounted) setState(() => _error = '读取或保存位置失败，已保留当前内容，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final note = _item?.note;
    if (_busy || note == null) return;
    unawaited(FeedbackScope.of(context).tap());
    setState(() => _busy = true);
    try {
      await _audio.stop();
      if (!mounted) return;
      await context.push('/decks/${note.deckId}/edit/${note.id}');
      if (mounted) await _open();
    } catch (_) {
      if (mounted) setState(() => _error = '编辑页面打开失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _favorite() async {
    final item = _item;
    if (_busy || item == null) return;
    unawaited(FeedbackScope.of(context).tap());
    setState(() => _busy = true);
    try {
      final repository = ref.read(studyRepositoryProvider);
      await repository.setFavorite(item.card.id, !item.card.isFavorite);
      final updated = await repository.getStudyCard(item.card.id);
      if (mounted) setState(() => _item = updated);
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _content(String value) => CardContent(
    source: value,
    media: ref.read(mediaRepositoryProvider),
    audio: _audio,
  );

  Widget _face(StudyCard item) {
    final note = item.note;
    if (note.type.isChoice) {
      final source = ChoiceQuestion.fromFields(note.type, note.fields);
      return ChoiceCardFace(
        key: ValueKey(
          'recite-${note.id}-${note.modifiedAtUtc.millisecondsSinceEpoch}',
        ),
        question: ChoiceQuestion(
          type: source.type,
          prompt: source.prompt,
          options: source.options,
          correctIndexes: source.correctIndexes,
          explanation: source.explanation,
        ),
        media: ref.read(mediaRepositoryProvider),
        audio: _audio,
        answerVisible: true,
        onReveal: () {},
        enabled: false,
        readingOnly: true,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (note.type == NoteType.cloze) ...[
          _content(ClozeParser().renderReading(note.fields['text'] ?? '')),
          if ((note.fields['extra'] ?? '').isNotEmpty) ...[
            const Divider(height: 32),
            _content(note.fields['extra']!),
          ],
        ] else ...[
          _content(note.fields['front'] ?? ''),
          const Divider(height: 32),
          Text('答案', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 12),
          _content(
            (note.fields['back'] ?? '').isEmpty
                ? '（空白答案）'
                : note.fields['back']!,
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audio.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final round = _round;
    final item = _item;
    return PageFrame(
      title: '背卡模式',
      header: const TouhouTag(TouhouPlace.school),
      subtitle: '直接阅读题目与答案；浏览不会计入学习评分或改变复习日期。',
      scrollController: _scroll,
      actions: [
        IconButton(
          tooltip: item?.card.isFavorite == true ? '取消收藏' : '收藏卡片',
          onPressed: _busy || item == null ? null : _favorite,
          icon: Icon(
            item?.card.isFavorite == true
                ? Icons.bookmark
                : Icons.bookmark_border,
          ),
        ),
        IconButton(
          tooltip: '编辑卡片',
          onPressed: _busy || item == null ? null : _edit,
          icon: const Icon(Icons.edit_outlined),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (round != null) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('包含子章节'),
              value: round.includeChildren,
              onChanged: _busy
                  ? null
                  : (value) {
                      unawaited(FeedbackScope.of(context).tap());
                      unawaited(_open(children: value));
                    },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('随机顺序'),
              subtitle: const Text('关闭时按章节顺序浏览；每条填空笔记只显示一次。'),
              value: round.random,
              onChanged: _busy
                  ? null
                  : (value) {
                      unawaited(FeedbackScope.of(context).tap());
                      unawaited(_open(random: value));
                    },
            ),
          ],
          if (_busy) const LinearProgressIndicator(semanticsLabel: '正在读取背卡内容'),
          if (_error != null) ...[
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            const SizedBox(height: 12),
            PressableAction(label: '重新读取', onPressed: _busy ? null : _open),
          ],
          if (round != null && round.noteIds.isEmpty && !_busy)
            const Text('当前范围没有可背诵内容，请调整子章节范围或先导入卡片。'),
          if (round != null && item != null) ...[
            const SizedBox(height: 16),
            Semantics(
              liveRegion: true,
              child: Text('第 ${_index + 1} / ${round.noteIds.length} 条'),
            ),
            Text(item.deckName, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: (_index + 1) / round.noteIds.length),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: _face(item),
              ),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                PressableAction(
                  label: '上一条',
                  onPressed: _busy || _index == 0 ? null : () => _move(-1),
                ),
                PressableAction(
                  label: '下一条',
                  onPressed: _busy || _index + 1 >= round.noteIds.length
                      ? null
                      : () => _move(1),
                ),
              ],
            ),
            if (_index + 1 == round.noteIds.length) ...[
              const SizedBox(height: 16),
              const Text('已到最后一条，阅读位置已保存在本机。'),
            ],
          ],
        ],
      ),
    );
  }
}
