import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';
import '../data/note_repository.dart';
import '../domain/cloze_parser.dart';
import '../domain/note.dart';

class NoteEditorPage extends ConsumerStatefulWidget {
  const NoteEditorPage({super.key, required this.deckId, this.noteId});
  final int deckId;
  final int? noteId;
  @override
  ConsumerState<NoteEditorPage> createState() => _NoteEditorPageState();
}

class _NoteEditorPageState extends ConsumerState<NoteEditorPage> {
  final _front = TextEditingController();
  final _back = TextEditingController();
  final _tags = TextEditingController();
  NoteType _type = NoteType.basic;
  Note? _original;
  bool _loading = false;
  bool _dirty = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    if (widget.noteId != null) {
      _loading = true;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final note = await ref
          .read(noteRepositoryProvider)
          .getNote(widget.noteId!);
      if (!mounted) return;
      _original = note;
      _type = note.type;
      _front.text =
          note.fields[_type == NoteType.basic ? 'front' : 'text'] ?? '';
      _back.text =
          note.fields[_type == NoteType.basic ? 'back' : 'extra'] ?? '';
      _tags.text = note.tags.join(' ');
      setState(() => _loading = false);
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadError = '卡片读取失败，请返回后重试。';
        });
      }
    }
  }

  @override
  void dispose() {
    _front.dispose();
    _back.dispose();
    _tags.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final repository = ref.read(noteRepositoryProvider);
    final tags = _tags.text.split(RegExp(r'[\s,，]+'));
    try {
      if (_original == null) {
        if (_type == NoteType.basic) {
          await repository.createBasicNote(
            deckId: widget.deckId,
            front: _front.text,
            back: _back.text,
            tags: tags,
          );
        } else {
          await repository.createClozeNote(
            deckId: widget.deckId,
            text: _front.text,
            extra: _back.text,
            tags: tags,
          );
        }
      } else {
        final note = Note(
          id: _original!.id,
          deckId: widget.deckId,
          type: _type,
          fields: _type == NoteType.basic
              ? {'front': _front.text, 'back': _back.text}
              : {'text': _front.text, 'extra': _back.text},
          tags: tags,
          createdAtUtc: _original!.createdAtUtc,
          modifiedAtUtc: DateTime.now(),
        );
        try {
          await repository.updateNote(note);
        } on ClozeRemovalConfirmation catch (error) {
          if (!mounted ||
              !await confirmRemoval(
                context,
                '${error.toString()}\n对应卡片的学习进度也会删除。',
              )) {
            return;
          }
          await repository.updateNote(note, allowCardRemoval: true);
        }
      }
      if (!mounted) return;
      setState(() => _dirty = false);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      context.pop();
    } catch (error) {
      if (mounted) showActionError(context, error);
    }
  }

  Future<void> _discard() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('放弃修改？'),
        content: const Text('尚未保存的内容会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('放弃修改'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) {
      setState(() => _dirty = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _discard();
    },
    child: PageFrame(
      title: widget.noteId == null ? '新建卡片' : '编辑卡片',
      child: _loading
          ? const LinearProgressIndicator()
          : _loadError != null
          ? Text(_loadError!)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<NoteType>(
                  segments: const [
                    ButtonSegment(value: NoteType.basic, label: Text('基础卡')),
                    ButtonSegment(value: NoteType.cloze, label: Text('填空卡')),
                  ],
                  selected: {_type},
                  onSelectionChanged: widget.noteId != null
                      ? null
                      : (value) => setState(() {
                          _type = value.single;
                          _dirty = true;
                        }),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: _front,
                  minLines: 4,
                  maxLines: 12,
                  onChanged: (_) => setState(() => _dirty = true),
                  decoration: InputDecoration(
                    labelText: _type == NoteType.basic ? '正面 · 问题' : '填空原文',
                    alignLabelWithHint: true,
                    helperText: _type == NoteType.cloze
                        ? '示例：硫酸铜晶体呈 {{c1::蓝色::颜色}}'
                        : null,
                    helperMaxLines: 3,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _back,
                  minLines: 3,
                  maxLines: 10,
                  onChanged: (_) => setState(() => _dirty = true),
                  decoration: InputDecoration(
                    labelText: _type == NoteType.basic ? '背面 · 答案' : '补充说明',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _tags,
                  onChanged: (_) => setState(() => _dirty = true),
                  decoration: const InputDecoration(
                    labelText: '标签',
                    hintText: '用空格或逗号分隔',
                  ),
                ),
                if (_type == NoteType.cloze) ...[
                  const SizedBox(height: 20),
                  Text(
                    '将生成 ${ClozeParser().indexes(_front.text).length} 张填空卡',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 28),
                PressableAction(label: '保存卡片', onPressed: _save),
              ],
            ),
    ),
  );
}
