import 'package:flutter/material.dart';

import '../../../core/content/card_content.dart';
import '../../../core/media/local_audio_controller.dart';
import '../../../core/media/media_repository.dart';
import '../../decks/domain/cloze_parser.dart';
import '../../decks/domain/note.dart';
import '../../study/domain/study_card.dart';

class PracticeCardFace extends StatelessWidget {
  const PracticeCardFace({
    super.key,
    required this.item,
    required this.answerVisible,
    required this.media,
    required this.audio,
  });
  final StudyCard item;
  final bool answerVisible;
  final MediaRepository media;
  final LocalAudioController audio;

  Widget _content(String source) =>
      CardContent(source: source, media: media, audio: audio);

  @override
  Widget build(BuildContext context) {
    final fields = item.note.fields;
    final basic = item.note.type == NoteType.basic;
    final parser = ClozeParser();
    final question = basic
        ? fields['front'] ?? ''
        : parser.renderQuestion(fields['text'] ?? '', item.card.clozeIndex!);
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
                if (answerVisible) ...[
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
      ],
    );
  }
}
