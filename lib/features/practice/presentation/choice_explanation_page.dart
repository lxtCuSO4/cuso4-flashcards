import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/content/card_content.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/media/local_audio_controller.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';
import '../../../core/widgets/touhou_tag.dart';
import '../../decks/domain/choice_attempt.dart';
import '../../decks/domain/choice_question.dart';

/// A temporary page: navigation never grades again or writes practice data.
class ChoiceExplanationPage extends StatefulWidget {
  const ChoiceExplanationPage({
    super.key,
    required this.question,
    required this.attempt,
    required this.media,
    required this.deckName,
    required this.position,
    required this.total,
  });
  final ChoiceQuestion question;
  final ChoiceAttemptSnapshot attempt;
  final MediaRepository media;
  final String deckName;
  final int position;
  final int total;

  @override
  State<ChoiceExplanationPage> createState() => _ChoiceExplanationPageState();
}

class _ChoiceExplanationPageState extends State<ChoiceExplanationPage>
    with WidgetsBindingObserver {
  late final LocalAudioController _audio;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _audio = LocalAudioController(widget.media);
    WidgetsBinding.instance.addObserver(this);
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

  void _next() {
    if (_leaving) return;
    setState(() => _leaving = true);
    Navigator.of(context).pop(true);
  }

  void _back() {
    if (_leaving) return;
    setState(() => _leaving = true);
    unawaited(FeedbackScope.of(context).tap());
    Navigator.of(context).pop(false);
  }

  Widget _content(String source) =>
      CardContent(source: source, media: widget.media, audio: _audio);

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    final attempt = widget.attempt;
    final correct = attempt.attempted && question.isCorrect(attempt.selected);
    final scheme = Theme.of(context).colorScheme;
    return PageFrame(
      key: const ValueKey('choice-explanation-page'),
      title: '题目解析',
      header: const TouhouTag(TouhouPlace.study),
      bottomBar: Material(
        color: scheme.surface,
        elevation: 6,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 912),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('explanation-back'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 52),
                        ),
                        onPressed: _leaving ? null : _back,
                        child: const Text('返回题目', textAlign: TextAlign.center),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PressableAction(
                        key: const ValueKey('explanation-next'),
                        label: widget.position == widget.total ? '完成本轮' : '下一题',
                        onPressed: _leaving ? null : _next,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '第 ${widget.position} / ${widget.total} 题 · ${question.type.label}',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          Text(widget.deckName),
          const SizedBox(height: 24),
          Semantics(
            liveRegion: true,
            child: Text(
              !attempt.attempted
                  ? '未作答'
                  : correct
                  ? '回答正确'
                  : '回答错误',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: attempt.attempted && !correct
                    ? scheme.error
                    : scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (attempt.attempted)
            Text('你的答案：${attempt.letters(attempt.selected)}'),
          Text('正确答案：${attempt.letters(question.correctIndexes)}'),
          if (attempt.attempted && !correct) ...[
            if (attempt.selected.difference(question.correctIndexes).isNotEmpty)
              Text(
                '错选：${attempt.letters(attempt.selected.difference(question.correctIndexes))}',
              ),
            if (question.correctIndexes.difference(attempt.selected).isNotEmpty)
              Text(
                '漏选：${attempt.letters(question.correctIndexes.difference(attempt.selected))}',
              ),
          ],
          const SizedBox(height: 24),
          Text('正确选项', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          for (final index in attempt.order.where(
            question.correctIndexes.contains,
          )) ...[
            Text(
              '选项 ${attempt.letters([index])}',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            _content(question.options[index]),
            const SizedBox(height: 16),
          ],
          const Divider(height: 32),
          Text('解析', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          if (question.explanation.trim().isEmpty)
            const Text('本题未提供解析')
          else
            _content(question.explanation),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
