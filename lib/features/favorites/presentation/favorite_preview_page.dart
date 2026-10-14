import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/content/card_content.dart';
import '../../../core/media/local_audio_controller.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';
import '../../decks/domain/cloze_parser.dart';
import '../../decks/domain/note.dart';
import '../../study/domain/study_card.dart';

class FavoritePreviewPage extends ConsumerStatefulWidget {
  const FavoritePreviewPage({super.key, required this.cardId});
  final int cardId;
  @override
  ConsumerState<FavoritePreviewPage> createState() =>
      _FavoritePreviewPageState();
}

class _FavoritePreviewPageState extends ConsumerState<FavoritePreviewPage>
    with WidgetsBindingObserver {
  late Future<StudyCard> _card;
  late final LocalAudioController _audio;
  bool _answerVisible = false;

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

  @override
  Widget build(BuildContext context) => PageFrame(
    title: '收藏预览',
    subtitle: '仅预览，不修改学习进度',
    child: FutureBuilder<StudyCard>(
      future: _card,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const LinearProgressIndicator();
        }
        final item = snapshot.data;
        if (snapshot.hasError || item == null) {
          return Column(
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
          );
        }
        final fields = item.note.fields;
        final basic = item.note.type == NoteType.basic;
        final parser = ClozeParser();
        final question = basic
            ? fields['front'] ?? ''
            : parser.renderQuestion(
                fields['text'] ?? '',
                item.card.clozeIndex!,
              );
        final answer = basic
            ? fields['back'] ?? ''
            : parser.renderAnswer(fields['text'] ?? '', item.card.clozeIndex!);
        return Column(
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
        );
      },
    ),
  );
}
