import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/media/prepared_image.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';
import '../application/editor_image_picker.dart';
import '../data/note_repository.dart';
import '../domain/cloze_parser.dart';
import '../domain/note.dart';
import 'note_preview_page.dart';

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
  bool _saving = false;
  bool _picking = false;
  bool _discarding = false;
  final _images = <String, PreparedImage>{};
  bool get _busy => _saving || _picking;
  Map<String, String> get _fields => _type == NoteType.basic
      ? {'front': _front.text, 'back': _back.text}
      : {'text': _front.text, 'extra': _back.text};
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
    if (_busy) return;
    setState(() => _saving = true);
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
            images: _images.values,
          );
        } else {
          await repository.createClozeNote(
            deckId: widget.deckId,
            text: _front.text,
            extra: _back.text,
            tags: tags,
            images: _images.values,
          );
        }
      } else {
        final note = Note(
          id: _original!.id,
          deckId: widget.deckId,
          type: _type,
          fields: {..._original!.fields, ..._fields},
          tags: tags,
          createdAtUtc: _original!.createdAtUtc,
          modifiedAtUtc: DateTime.now(),
        );
        try {
          await repository.updateNote(note, images: _images.values);
        } on ClozeRemovalConfirmation catch (error) {
          if (!mounted ||
              !await confirmRemoval(
                context,
                '${error.toString()}\n对应卡片的学习进度也会删除。',
              )) {
            return;
          }
          await repository.updateNote(
            note,
            allowCardRemoval: true,
            images: _images.values,
          );
        }
      }
      if (!mounted) return;
      unawaited(cleanUpUnusedMedia(repository.media));
      setState(() {
        _dirty = false;
        _saving = false;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      context.pop();
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _insertImage(TextEditingController controller) async {
    if (_busy) return;
    final value = controller.value;
    FocusScope.of(context).unfocus();
    setState(() => _picking = true);
    try {
      final image = await ref.read(editorImagePickerProvider)();
      if (!mounted || image == null) return;
      final total = _images.values.fold(
        0,
        (sum, item) => sum + item.bytes.length,
      );
      if (!_images.containsKey(image.hash) &&
          total + image.bytes.length > PreparedImage.maxDraftBytes) {
        throw ArgumentError('本次编辑选入图片合计超过 30 MiB，请先保存后重新编辑。');
      }
      final selection = value.selection;
      final start = selection.isValid ? selection.start : value.text.length;
      final end = selection.isValid ? selection.end : value.text.length;
      final markup = '\n<img src="${image.token}">\n';
      controller.value = TextEditingValue(
        text: value.text.replaceRange(start, end, markup),
        selection: TextSelection.collapsed(offset: start + markup.length),
      );
      setState(() {
        _images[image.hash] = image;
        _dirty = true;
      });
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _preview() async {
    FocusScope.of(context).unfocus();
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NotePreviewPage(
          type: _type,
          front: _front.text,
          back: _back.text,
          media: ref.read(mediaRepositoryProvider),
          draftImages: Map.unmodifiable({
            for (final image in _images.values) image.token: image.bytes,
          }),
        ),
      ),
    );
  }

  Future<void> _discard() async {
    if (_busy || _discarding) return;
    _discarding = true;
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
    _discarding = false;
    if (leave == true && mounted) {
      setState(() => _dirty = false);
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) context.pop();
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty && !_busy,
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
                  onSelectionChanged: widget.noteId != null || _busy
                      ? null
                      : (value) => setState(() {
                          _type = value.single;
                          _dirty = true;
                        }),
                ),
                const SizedBox(height: 24),
                TextField(
                  key: const ValueKey('note-front'),
                  enabled: !_busy,
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
                const SizedBox(height: 8),
                PressableAction(
                  label: _type == NoteType.basic ? '正面插入图片' : '原文插入图片',
                  onPressed: _busy ? null : () => _insertImage(_front),
                ),
                const SizedBox(height: 20),
                TextField(
                  key: const ValueKey('note-back'),
                  enabled: !_busy,
                  controller: _back,
                  minLines: 3,
                  maxLines: 10,
                  onChanged: (_) => setState(() => _dirty = true),
                  decoration: InputDecoration(
                    labelText: _type == NoteType.basic ? '背面 · 答案' : '补充说明',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                PressableAction(
                  label: _type == NoteType.basic ? '背面插入图片' : '补充插入图片',
                  onPressed: _busy ? null : () => _insertImage(_back),
                ),
                const SizedBox(height: 8),
                Text(
                  '支持 PNG、JPG、GIF、WebP，单张 ≤ 10 MiB、1600 万像素。图片标记可在下方预览中查看。',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 20),
                TextField(
                  enabled: !_busy,
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
                PressableAction(
                  label: '预览卡片',
                  onPressed: _busy ? null : _preview,
                ),
                const SizedBox(height: 12),
                PressableAction(
                  label: _saving ? '正在保存…' : '保存卡片',
                  onPressed: _busy ? null : _save,
                ),
              ],
            ),
    ),
  );
}
