import 'package:flutter/material.dart';

import '../../../core/widgets/pressable_action.dart';
import '../domain/choice_question.dart';

class ChoiceEditorFields extends StatelessWidget {
  const ChoiceEditorFields({
    super.key,
    required this.options,
    required this.correctIndexes,
    required this.enabled,
    required this.shuffle,
    required this.onCorrect,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
    required this.onShuffle,
    required this.onInsertImage,
  });
  final List<TextEditingController> options;
  final Set<int> correctIndexes;
  final bool enabled, shuffle;
  final void Function(int, bool) onCorrect;
  final VoidCallback onAdd, onChanged;
  final ValueChanged<int> onRemove, onInsertImage;
  final ValueChanged<bool> onShuffle;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('填写选项，并勾选正确答案。'),
      const SizedBox(height: 12),
      for (var i = 0; i < options.length; i++) ...[
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CheckboxListTile(
                  key: ValueKey('choice-correct-$i'),
                  contentPadding: EdgeInsets.zero,
                  title: Text('${String.fromCharCode(65 + i)} · 正确答案'),
                  value: correctIndexes.contains(i),
                  onChanged: enabled ? (v) => onCorrect(i, v ?? false) : null,
                ),
                TextField(
                  key: ValueKey('choice-editor-option-$i'),
                  controller: options[i],
                  enabled: enabled,
                  minLines: 1,
                  maxLines: 5,
                  onChanged: (_) => onChanged(),
                  decoration: InputDecoration(
                    labelText: '选项 ${String.fromCharCode(65 + i)}',
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: enabled ? () => onInsertImage(i) : null,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('插入图片'),
                    ),
                    TextButton.icon(
                      key: ValueKey('choice-remove-$i'),
                      onPressed: enabled && options.length > 2
                          ? () => onRemove(i)
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                      label: const Text('删除选项'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      PressableAction(
        label: '添加选项',
        onPressed: enabled && options.length < ChoiceQuestion.maxOptions
            ? onAdd
            : null,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('打乱选项'),
        subtitle: const Text('每次作答重新排列；选项含“以上皆是”等顺序关系时请关闭'),
        value: shuffle,
        onChanged: enabled ? onShuffle : null,
      ),
      const SizedBox(height: 16),
    ],
  );
}
