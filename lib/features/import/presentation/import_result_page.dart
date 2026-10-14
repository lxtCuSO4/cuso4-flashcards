import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/pressable_action.dart';
import '../domain/import_report.dart';

class ImportResultPanel extends StatelessWidget {
  const ImportResultPanel({super.key, required this.report});
  final ImportReport report;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          report.cards > 0 ? Icons.check_circle_outline : Icons.info_outline,
          size: 56,
          color: scheme.secondary,
        ),
        const SizedBox(height: 16),
        Text(
          report.cards > 0 ? '导入完成' : '未找到支持的卡片',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text('只保留卡片内容和本地媒体，所有导入卡片均从新卡开始。', textAlign: TextAlign.center),
        const SizedBox(height: 24),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Wrap(
              spacing: 24,
              runSpacing: 20,
              children: [
                _Count('牌组路径', report.decks),
                _Count('笔记', report.notes),
                _Count('卡片', report.cards),
                _Count('新增媒体文件', report.media),
              ],
            ),
          ),
        ),
        if (report.skipped > 0 ||
            report.missingMedia > 0 ||
            report.unsupportedMedia > 0) ...[
          const SizedBox(height: 20),
          Text('需要留意', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (report.skipped > 0) Text('跳过 ${report.skipped} 条笔记：'),
          for (final entry in report.skippedReasons.entries)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${_reason(entry.key)}：${entry.value} 条'),
            ),
          if (report.missingMedia > 0)
            Text('缺失媒体：${report.missingMedia} 个。卡片文字已保留。'),
          if (report.unsupportedMedia > 0)
            Text('不支持或过大的媒体：${report.unsupportedMedia} 个。'),
          const SizedBox(height: 8),
          const Text('支持标准基础卡与填空卡，不执行 Anki 自定义模板或脚本。'),
        ],
        const SizedBox(height: 28),
        PressableAction(label: '查看牌组', onPressed: () => context.go('/decks')),
      ],
    );
  }

  String _reason(String value) => switch (value) {
    'unsupportedTemplate' => '不支持的字段或自定义模板',
    'unsupportedClozeCards' => '填空编号与卡片不一致',
    'emptyFront' => '卡片正面为空',
    'missingDeck' => '找不到对应牌组',
    _ => '无法转换的卡片',
  };
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.count);
  final String label;
  final int count;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 128,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$count', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(label),
      ],
    ),
  );
}
