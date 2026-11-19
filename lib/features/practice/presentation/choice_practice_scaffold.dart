import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/feedback/feedback_controller.dart';
import '../../../core/media/local_audio_controller.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/widgets/touhou_tag.dart';
import '../../decks/domain/choice_attempt.dart';
import '../../decks/domain/choice_question.dart';
import '../../decks/presentation/choice_card_face.dart';
import '../../study/domain/study_card.dart';

class ChoicePracticeScaffold extends StatelessWidget {
  const ChoicePracticeScaffold({
    super.key,
    required this.title,
    required this.item,
    required this.media,
    required this.audio,
    required this.answerVisible,
    required this.onReveal,
    required this.onReview,
    required this.onNext,
    required this.nextLabel,
    this.position = 1,
    this.total = 1,
    this.busy = false,
    this.place = TouhouPlace.bamboo,
    this.onSubmit,
    this.onFavorite,
    this.onEdit,
    this.onSkip,
  });
  final String title;
  final StudyCard item;
  final MediaRepository media;
  final LocalAudioController audio;
  final bool answerVisible;
  final bool busy;
  final int position;
  final int total;
  final TouhouPlace place;
  final VoidCallback onReveal;
  final ValueChanged<ChoiceAttemptSnapshot> onReview;
  final Future<void> Function(Set<int>)? onSubmit;
  final FutureOr<void> Function() onNext;
  final String nextLabel;
  final Future<void> Function()? onFavorite;
  final Future<void> Function()? onEdit;
  final Future<void> Function()? onSkip;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        if (onFavorite != null)
          IconButton(
            tooltip: item.card.isFavorite ? '取消收藏' : '收藏卡片',
            onPressed: busy ? null : onFavorite,
            icon: Icon(
              item.card.isFavorite ? Icons.bookmark : Icons.bookmark_border,
            ),
          ),
        if (onEdit != null)
          IconButton(
            tooltip: '编辑卡片',
            onPressed: busy ? null : onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
        if (onSkip != null && !answerVisible)
          PopupMenuButton<String>(
            tooltip: '更多操作',
            enabled: !busy,
            onSelected: (_) {
              unawaited(FeedbackScope.of(context).tap());
              unawaited(onSkip!());
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'skip', child: Text('跳过此题')),
            ],
          ),
      ],
    ),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        TouhouTag(place, margin: EdgeInsets.zero),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              '第 $position / $total 张',
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Tooltip(
                      message: item.deckName,
                      child: Text(
                        '${item.note.type.label} · ${item.deckName}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: (position - 1) / total,
                      minHeight: 2,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: KeyedSubtree(
                  key: ValueKey('practice-card-${item.card.id}'),
                  child: ChoiceCardFace(
                    key: ValueKey('compact-choice-${item.card.id}'),
                    question: ChoiceQuestion.fromFields(
                      item.note.type,
                      item.note.fields,
                    ),
                    media: media,
                    audio: audio,
                    answerVisible: answerVisible,
                    enabled: !busy,
                    onReveal: onReveal,
                    onSubmit: onSubmit,
                    onReview: onReview,
                    adaptive: true,
                    showExplanation: false,
                    onNext: onNext,
                    nextLabel: nextLabel,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
