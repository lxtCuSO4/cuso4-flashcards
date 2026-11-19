import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/content/card_content.dart';
import '../../../core/media/local_audio_controller.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';
import '../../../core/widgets/touhou_tag.dart';
import '../../decks/domain/cloze_parser.dart';
import '../../decks/domain/choice_question.dart';
import '../../decks/domain/note.dart';
import '../../decks/domain/choice_attempt.dart';
import '../../practice/presentation/choice_practice_scaffold.dart';
import '../../practice/presentation/choice_explanation_page.dart';
import '../../study/domain/study_card.dart';

class FavoritePreviewPage extends ConsumerStatefulWidget {
  const FavoritePreviewPage({
    super.key,
    required this.cardId,
    this.title = '收藏预览',
  });
  final int cardId;
  final String title;
  @override
  ConsumerState<FavoritePreviewPage> createState() =>
      _FavoritePreviewPageState();
}

class _FavoritePreviewPageState extends ConsumerState<FavoritePreviewPage>
    with WidgetsBindingObserver {
  late Future<StudyCard> _card;
  late final LocalAudioController _audio;
  bool _answerVisible = false;
  bool _reviewOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _audio = LocalAudioController(ref.read(mediaRepositoryProvider));
    _card = ref.read(studyRepositoryProvider).getStudyCard(widget.cardId);
  }

  @override
  void didUpdateWidget(FavoritePreviewPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cardId != widget.cardId) {
      unawaited(_audio.stop());
      _answerVisible = false;
      _card = ref.read(studyRepositoryProvider).getStudyCard(widget.cardId);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_audio.stop());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _audio.dispose();
    super.dispose();
  }

  Widget _content(String source) => CardContent(
    source: source,
    media: ref.read(mediaRepositoryProvider),
    audio: _audio,
  );

  Widget _frame(Widget child) => PageFrame(
    exterior: false,
    title: widget.title,
    subtitle: widget.title == '收藏预览' ? '仅预览，不修改学习进度' : '仅预览，不修改学习进度或错题列表',
    child: child,
  );

  Future<void> _review(StudyCard item, ChoiceAttemptSnapshot attempt) async {
    if (_reviewOpen) return;
    _reviewOpen = true;
    try {
      await _audio.stop();
      if (!mounted) return;
      await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ChoiceExplanationPage(
            question: ChoiceQuestion.fromFields(
              item.note.type,
              item.note.fields,
            ),
            attempt: attempt,
            media: ref.read(mediaRepositoryProvider),
            deckName: item.deckName,
            position: 1,
            total: 1,
            allowAdvance: false,
          ),
        ),
      );
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      _reviewOpen = false;
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<StudyCard>(
    future: _card,
    builder: (context, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) {
        return _frame(const LinearProgressIndicator());
      }
      final item = snapshot.data;
      if (snapshot.hasError || item == null) {
        return _frame(
          Column(
            children: [
              const Text('卡片已删除或暂时无法加载，请返回收藏列表或重试。'),
              const SizedBox(height: 16),
              PressableAction(
                label: '重试加载卡片',
                onPressed: () => setState(() {
                  _answerVisible = false;
                  _card = ref
                      .read(studyRepositoryProvider)
                      .getStudyCard(widget.cardId);
                }),
              ),
            ],
          ),
        );
      }
      final fields = item.note.fields;
      if (item.note.type.isChoice) {
        return ChoicePracticeScaffold(
          title: widget.title,
          item: item,
          media: ref.read(mediaRepositoryProvider),
          audio: _audio,
          answerVisible: _answerVisible,
          place: widget.title == '错题预览'
              ? TouhouPlace.bamboo
              : TouhouPlace.bookmarks,
          onReveal: () => setState(() => _answerVisible = true),
          onReview: (attempt) => unawaited(_review(item, attempt)),
          onNext: () => setState(() => _answerVisible = false),
          nextLabel: '重新作答',
        );
      }
      final basic = item.note.type == NoteType.basic;
      final parser = ClozeParser();
      final question = basic
          ? fields['front'] ?? ''
          : parser.renderQuestion(fields['text'] ?? '', item.card.clozeIndex!);
      final answer = basic
          ? fields['back'] ?? ''
          : parser.renderAnswer(fields['text'] ?? '', item.card.clozeIndex!);
      return _frame(
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(item.deckName, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _content(question),
                    if (_answerVisible) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Divider(),
                      ),
                      Text('答案', style: Theme.of(context).textTheme.labelLarge),
                      const SizedBox(height: 12),
                      _content(answer.isEmpty ? '（空白答案）' : answer),
                      if (!basic && (fields['extra'] ?? '').isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _content(fields['extra']!),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            PressableAction(
              label: _answerVisible ? '隐藏答案' : '显示答案',
              onPressed: () => setState(() => _answerVisible = !_answerVisible),
            ),
          ],
        ),
      );
    },
  );
}
