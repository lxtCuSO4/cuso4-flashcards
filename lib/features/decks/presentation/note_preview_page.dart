import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../core/content/card_content.dart';
import '../../../core/media/local_audio_controller.dart';
import '../../../core/media/media_repository.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';
import '../domain/cloze_parser.dart';
import '../domain/choice_question.dart';
import '../domain/note.dart';
import 'choice_card_face.dart';

class NotePreviewPage extends StatefulWidget {
  const NotePreviewPage({
    super.key,
    required this.type,
    required this.front,
    required this.back,
    required this.media,
    required this.draftImages,
    this.choice,
  });
  final NoteType type;
  final ChoiceQuestion? choice;
  final String front;
  final String back;
  final MediaRepository media;
  final Map<String, Uint8List> draftImages;
  @override
  State<NotePreviewPage> createState() => _NotePreviewPageState();
}

class _NotePreviewPageState extends State<NotePreviewPage> {
  late final _audio = LocalAudioController(widget.media);
  late final _indexes = ClozeParser().indexes(widget.front);
  late int? _index = _indexes.firstOrNull;
  bool _answer = false;
  @override
  void dispose() {
    _audio.dispose();
    super.dispose();
  }

  Widget _content(String value) => CardContent(
    source: value,
    media: widget.media,
    audio: _audio,
    draftImages: widget.draftImages,
  );

  @override
  Widget build(BuildContext context) {
    final basic = widget.type == NoteType.basic;
    final valid =
        widget.type.isChoice ||
        (basic ? widget.front.trim().isNotEmpty : _index != null);
    final parser = ClozeParser();
    final question = widget.type.isChoice || basic || _index == null
        ? widget.front
        : parser.renderQuestion(widget.front, _index!);
    final answer = widget.type.isChoice || basic
        ? widget.back
        : parser.renderAnswer(widget.front, _index ?? 1);
    return PageFrame(
      title: '卡片预览',
      subtitle: '预览当前编辑内容，不会保存或影响学习进度。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.type == NoteType.cloze && _indexes.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final index in _indexes)
                  ChoiceChip(
                    label: Text('填空 $index'),
                    selected: index == _index,
                    onSelected: (_) => setState(() {
                      _index = index;
                      _answer = false;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
          if (!valid) ...[
            Text(basic ? '正面还没有内容。返回编辑后再预览。' : '未找到有效填空。请添加 {{c1::内容}} 后再预览。'),
            const SizedBox(height: 16),
          ],
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.type.isChoice)
                    ChoiceCardFace(
                      question: widget.choice!,
                      media: widget.media,
                      audio: _audio,
                      draftImages: widget.draftImages,
                      answerVisible: _answer,
                      onReveal: () => setState(() => _answer = true),
                    )
                  else
                    _content(question),
                  if (_answer && !widget.type.isChoice) ...[
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(),
                    ),
                    Text('答案', style: Theme.of(context).textTheme.labelLarge),
                    const SizedBox(height: 12),
                    _content(answer.isEmpty ? '（空白答案）' : answer),
                    if (!basic && widget.back.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _content(widget.back),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (!widget.type.isChoice || _answer)
            PressableAction(
              label: widget.type.isChoice
                  ? '重新作答'
                  : _answer
                  ? '隐藏答案'
                  : '显示答案',
              onPressed: valid
                  ? () => setState(() => _answer = !_answer)
                  : null,
            ),
        ],
      ),
    );
  }
}
