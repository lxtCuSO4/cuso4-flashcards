import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';
import '../../../core/widgets/touhou_tag.dart';
import '../data/choice_conversion_repository.dart';

class ChoiceConversionPage extends ConsumerStatefulWidget {
  const ChoiceConversionPage({super.key, required this.deckId});
  final int deckId;
  @override
  ConsumerState<ChoiceConversionPage> createState() =>
      _ChoiceConversionPageState();
}

class _ChoiceConversionPageState extends ConsumerState<ChoiceConversionPage> {
  ChoiceConversionPreview? _preview;
  String? _status;
  bool _busy = false;

  Future<void> _scan() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _preview = null;
      _status = null;
    });
    try {
      final preview = await ref
          .read(choiceConversionRepositoryProvider)
          .scan(widget.deckId);
      if (mounted) setState(() => _preview = preview);
    } catch (_) {
      if (mounted) setState(() => _status = '扫描失败，请确认牌组仍存在后重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _apply() async {
    final preview = _preview;
    if (_busy || preview == null || preview.total == 0) return;
    setState(() => _busy = true);
    try {
      final confirmed = await confirmRemoval(
        context,
        '将 ${preview.total} 条基础卡转换为可作答的选择题，包含子章节。学习进度、收藏和原解析均保留。',
        title: '确认转换选择题？',
        confirmLabel: '确认转换',
      );
      if (!confirmed || !mounted) return;
      final count = await ref
          .read(choiceConversionRepositoryProvider)
          .apply(preview);
      if (mounted) {
        setState(() {
          _preview = null;
          _status = '已转换 $count 条选择题，学习进度已保留。';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _preview = null;
          _status = error is StateError
              ? error.message.toString()
              : '转换未完成，本次修改已撤回，请重新扫描。';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: PageFrame(
      title: '识别已导入选择题',
      header: const TouhouTag(TouhouPlace.library),
      subtitle: '把已有题目变成可以点选作答的卡片。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('扫描当前牌组及其子章节，仅识别题干、连续 A–H 选项和明确答案齐全的基础卡。无法确定的题目继续保留为基础卡。'),
          const SizedBox(height: 16),
          const Text('先扫描，再确认转换。保留学习进度、复习记录、收藏、标签、图片和原解析，无需删除或重新导入。'),
          const SizedBox(height: 24),
          PressableAction(
            label: _preview == null ? '扫描基础卡' : '重新扫描',
            onPressed: _busy ? null : _scan,
          ),
          if (_busy) ...[
            const SizedBox(height: 16),
            const LinearProgressIndicator(),
          ],
          if (_preview case final preview?) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '扫描结果',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Text('可转为单选题：${preview.singleChoice} 条'),
                    Text('可转为多选题：${preview.multipleChoice} 条'),
                    Text('继续保留基础卡：${preview.retainedBasic} 条'),
                    const SizedBox(height: 12),
                    Text(
                      preview.total == 0
                          ? '没有找到可转换的题目，现有选择题和填空卡无需转换。'
                          : '本次扫描尚未修改任何卡片。',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            PressableAction(
              label: '转换为选择题',
              onPressed: _busy || preview.total == 0 ? null : _apply,
            ),
          ],
          if (_status != null) ...[
            const SizedBox(height: 20),
            Semantics(liveRegion: true, child: Text(_status!)),
          ],
        ],
      ),
    ),
  );
}
