import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';

class ImportRecoveryBanner extends ConsumerWidget {
  const ImportRecoveryBanner({
    super.key,
    this.onRetry,
    this.retryLabel = '前往导入',
  });
  final FutureOr<void> Function()? onRetry;
  final String retryLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(importRecoveryNoticeProvider).value;
    if (notice == null) return const SizedBox.shrink();
    final interrupted = notice.interruptedJobs > 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Semantics(
        liveRegion: true,
        child: Card(
          margin: EdgeInsets.zero,
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  interrupted ? '上次导入未完成' : '部分导入临时文件尚未清理',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  interrupted
                      ? '有 ${notice.interruptedJobs} 次导入意外中断，未自动继续。请重新选择原 .apkg 文件导入；已经保存的牌组和学习进度仍然保留。'
                      : '已保存的牌组可以继续学习，无需因此重新导入。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                  ),
                ),
                if (notice.cleanupFailures > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    '有 ${notice.cleanupFailures} 处临时文件未能安全清理，已保留，下次启动会重试。你可以继续使用应用。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSecondaryContainer,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (interrupted) ...[
                  PressableAction(label: retryLabel, onPressed: onRetry),
                  const SizedBox(height: 8),
                ],
                PressableAction(
                  label: '知道了',
                  onPressed: () async {
                    try {
                      await ref
                          .read(importRecoveryRepositoryProvider)
                          .acknowledge(notice);
                    } catch (error) {
                      if (context.mounted) showActionError(context, error);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
