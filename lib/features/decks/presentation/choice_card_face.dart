import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/content/card_content.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/media/local_audio_controller.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/widgets/pressable_action.dart';
import '../domain/choice_question.dart';
import '../domain/choice_attempt.dart';
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
    this.readingOnly = false,
    this.onSubmit,
    this.onReview,
    this.showExplanation = true,
    this.draftImages = const {},
  });
  final ChoiceQuestion question;
  final MediaRepository media;
  final LocalAudioController audio;
  final bool answerVisible;
  final VoidCallback onReveal;
  final bool enabled;
  final bool readingOnly;
  final Future<void> Function(Set<int>)? onSubmit;
  final ValueChanged<ChoiceAttemptSnapshot>? onReview;
  final bool showExplanation;
  final Map<String, Uint8List> draftImages;

  @override
  State<ChoiceCardFace> createState() => _ChoiceCardFaceState();
}

class _ChoiceCardFaceState extends State<ChoiceCardFace> {
  late List<int> _order;
  final _selected = <int>{};
  bool _attempted = false;
  bool _submitting = false;
  String? _submitError;

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
    _submitError = null;
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
    if (!widget.enabled || widget.answerVisible || _submitting) return;
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

  Future<void> _submit() async {
    if (_submitting ||
        !widget.enabled ||
        widget.answerVisible ||
        _selected.isEmpty) {
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    // The parent disables controls while saving; keep the original callbacks
    // so that rebuild cannot replace a successful reveal with a disabled no-op.
    final reveal = widget.onReveal;
    final review = widget.onReview;
    try {
      await widget.onSubmit?.call(Set.unmodifiable(_selected));
      if (!mounted) return;
      setState(() => _attempted = true);
      reveal();
      review?.call(_snapshot());
    } catch (error) {
      if (mounted) {
        setState(
          () => _submitError = error is StateError
              ? error.message
              : '答案保存失败，选择已保留，请重试提交。',
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  ChoiceAttemptSnapshot _snapshot() => ChoiceAttemptSnapshot(
    selected: _selected,
    order: _order,
    attempted: _attempted,
  );

  void _review() {
    if (!widget.enabled || _submitting) return;
    unawaited(FeedbackScope.of(context).tap());
    if (!widget.answerVisible) {
      setState(() => _attempted = false);
      widget.onReveal();
    }
    widget.onReview?.call(_snapshot());
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
        if (!widget.readingOnly)
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
                  : widget.readingOnly
                  ? (isAnswer ? '正确选项' : null)
                  : isAnswer
                  ? (selected ? '正确选项 · 已选' : '正确选项 · 未选')
                  : selected
                  ? '错选'
                  : null;
              final tint = revealed && selected && !isAnswer
                  ? scheme.error
                  : scheme.primary;
              return Semantics(
                checked: widget.readingOnly ? isAnswer : selected,
                inMutuallyExclusiveGroup:
                    question.type == NoteType.singleChoice,
                enabled: widget.enabled && !revealed && !_submitting,
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
                    onTap: widget.enabled && !revealed && !_submitting
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
                                    ? ((selected ||
                                              widget.readingOnly && isAnswer)
                                          ? Icons.radio_button_checked
                                          : Icons.radio_button_off)
                                    : ((selected ||
                                              widget.readingOnly && isAnswer)
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
            label: _submitting ? '正在保存…' : '提交答案',
            onPressed: !widget.enabled || _selected.isEmpty || _submitting
                ? null
                : _submit,
          ),
          if (_submitError case final error?)
            Semantics(
              liveRegion: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(error, style: TextStyle(color: scheme.error)),
              ),
            ),
          TextButton(
            onPressed: !widget.enabled || _submitting ? null : _review,
            child: Text(widget.onReview == null ? '直接看答案' : '查看解析'),
          ),
        ] else ...[
          const Divider(height: 32),
          if (!widget.readingOnly)
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
          if (widget.showExplanation && question.explanation.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('解析', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            _content(question.explanation),
          ],
          if (widget.onReview != null)
            TextButton(
              onPressed: widget.enabled && !_submitting ? _review : null,
              child: const Text('查看解析'),
            ),
        ],
      ],
    );
  }
}

extension on List<String> {
  String sortedLetters() => (this..sort()).join('、');
}
