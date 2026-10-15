import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/content/card_content.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/media/local_audio_controller.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/widgets/pressable_action.dart';
import '../domain/choice_question.dart';
import '../domain/note.dart';

class ChoiceCardFace extends StatefulWidget {
  const ChoiceCardFace({
    super.key,
    required this.question,
    required this.media,
    required this.audio,
    required this.answerVisible,
    required this.onReveal,
    this.enabled = true,
    this.draftImages = const {},
  });
  final ChoiceQuestion question;
  final MediaRepository media;
  final LocalAudioController audio;
  final bool answerVisible;
  final VoidCallback onReveal;
  final bool enabled;
  final Map<String, Uint8List> draftImages;

  @override
  State<ChoiceCardFace> createState() => _ChoiceCardFaceState();
}

class _ChoiceCardFaceState extends State<ChoiceCardFace> {
  late List<int> _order;
  final _selected = <int>{};
  bool _attempted = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  void _prepare() {
    _order = List.generate(widget.question.options.length, (i) => i);
    if (widget.question.shuffle) _order.shuffle();
    _selected.clear();
    _attempted = false;
  }

  @override
  void didUpdateWidget(ChoiceCardFace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.answerVisible && !widget.answerVisible) _prepare();
  }

  Widget _content(String source) => CardContent(
    source: source,
    media: widget.media,
    audio: widget.audio,
    draftImages: widget.draftImages,
  );

  void _choose(int index) {
    if (!widget.enabled || widget.answerVisible) return;
    unawaited(FeedbackScope.of(context).tap());
    setState(() {
      if (widget.question.type == NoteType.singleChoice) {
        _selected
          ..clear()
          ..add(index);
      } else if (!_selected.add(index)) {
        _selected.remove(index);
      }
    });
  }

  String _letters(Iterable<int> indexes) => indexes
      .map((index) => String.fromCharCode(65 + _order.indexOf(index)))
      .toList()
      .sortedLetters();

  @override
  Widget build(BuildContext context) {
    final question = widget.question;
    final scheme = Theme.of(context).colorScheme;
    final correct = question.isCorrect(_selected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          question.type.label,
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 12),
        _content(question.prompt),
        const SizedBox(height: 16),
        Text(
          question.type == NoteType.singleChoice
              ? '选择一个答案，再提交。'
              : '可选择多个答案；少选、多选或错选均判错。',
        ),
        const SizedBox(height: 12),
        for (var position = 0; position < _order.length; position++) ...[
          Builder(
            builder: (context) {
              final index = _order[position];
              final selected = _selected.contains(index);
              final isAnswer = question.correctIndexes.contains(index);
              final label = String.fromCharCode(65 + position);
              final revealed = widget.answerVisible;
              final status = !revealed
                  ? null
                  : isAnswer
                  ? (selected ? '正确选项 · 已选' : '正确选项 · 未选')
                  : selected
                  ? '错选'
                  : null;
              final tint = revealed && selected && !isAnswer
                  ? scheme.error
                  : scheme.primary;
              return Semantics(
                checked: selected,
                inMutuallyExclusiveGroup:
                    question.type == NoteType.singleChoice,
                enabled: widget.enabled && !revealed,
                child: Material(
                  color: selected || revealed && isAnswer
                      ? tint.withValues(alpha: .10)
                      : scheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(
                      color: selected || revealed && isAnswer
                          ? tint
                          : scheme.outlineVariant,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    key: ValueKey('choice-option-$index'),
                    onTap: widget.enabled && !revealed
                        ? () => _choose(index)
                        : null,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 56),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ExcludeSemantics(
                              child: Icon(
                                question.type == NoteType.singleChoice
                                    ? (selected
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off)
                                    : (selected
                                          ? Icons.check_box
                                          : Icons.check_box_outline_blank),
                                color: tint,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '选项 $label',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge,
                                  ),
                                  const SizedBox(height: 4),
                                  _content(question.options[index]),
                                  if (status != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      status,
                                      style: TextStyle(
                                        color: tint,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
        if (!widget.answerVisible) ...[
          PressableAction(
            label: '提交答案',
            onPressed: !widget.enabled || _selected.isEmpty
                ? null
                : () {
                    setState(() => _attempted = true);
                    widget.onReveal();
                  },
          ),
          TextButton(
            onPressed: !widget.enabled
                ? null
                : () {
                    unawaited(FeedbackScope.of(context).tap());
                    setState(() => _attempted = false);
                    widget.onReveal();
                  },
            child: const Text('直接看答案'),
          ),
        ] else ...[
          const Divider(height: 32),
          Semantics(
            liveRegion: true,
            child: Text(
              !_attempted
                  ? '未作答'
                  : correct
                  ? '回答正确'
                  : '回答错误',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: _attempted && !correct ? scheme.error : scheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_attempted) Text('你的答案：${_letters(_selected)}'),
          Text('正确答案：${_letters(question.correctIndexes)}'),
          if (_attempted && !correct) ...[
            if (_selected.difference(question.correctIndexes).isNotEmpty)
              Text(
                '错选：${_letters(_selected.difference(question.correctIndexes))}',
              ),
            if (question.correctIndexes.difference(_selected).isNotEmpty)
              Text(
                '漏选：${_letters(question.correctIndexes.difference(_selected))}',
              ),
          ],
          if (question.explanation.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('解析', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            _content(question.explanation),
          ],
        ],
      ],
    );
  }
}

extension on List<String> {
  String sortedLetters() => (this..sort()).join('、');
}
