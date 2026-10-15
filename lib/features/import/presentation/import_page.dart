import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../../app/providers.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';
import '../application/import_controller.dart';
import 'import_result_page.dart';
import 'import_recovery_notice.dart';

class ImportPage extends ConsumerWidget {
  const ImportPage({super.key});

  Future<void> _pick(ImportController controller) async {
    try {
      // .apkg has no universally registered Android MIME type. Let the native
      // document picker display all files and validate the extension ourselves.
      final file = await FilePicker.pickFile(dialogTitle: '选择 .apkg 牌组包');
      if (file == null) return;
      if (p.extension(file.name).toLowerCase() != '.apkg') {
        controller.selectionFailed('只支持 .apkg 牌组包，请重新选择。');
      } else if (file.path == null) {
        controller.selectionFailed('无法读取这个文件，请先将牌组包保存到手机本地。');
      } else {
        controller.select(File(file.path!));
      }
    } catch (_) {
      controller.selectionFailed('文件选择失败，请重试或先将文件保存到本地。');
    }
  }

  Future<void> _requestExit(
    BuildContext context,
    ImportController controller,
  ) async {
    if (!controller.busy) return;
    final cancel = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('正在导入'),
        content: const Text('请等待导入结束，或取消本次导入。取消后会回滚本次新增的卡片与媒体。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('继续等待'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('取消导入'),
          ),
        ],
      ),
    );
    if (cancel == true) controller.cancel();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(importControllerProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => PopScope(
        canPop: !controller.busy,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _requestExit(context, controller);
        },
        child: PageFrame(
          title: '导入牌组',
          subtitle: '在手机本地完成，不需要账户或网络。',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ImportRecoveryBanner(
                retryLabel: '重新选择文件',
                onRetry: controller.busy ? null : () => _pick(controller),
              ),
              controller.report != null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ImportResultPanel(report: controller.report!),
                        const SizedBox(height: 16),
                        TextButton(
                          onPressed: () => _pick(controller),
                          child: const Text('选择另一个牌组包'),
                        ),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.inventory_2_outlined,
                                  size: 36,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  controller.file == null
                                      ? '带上你的 Anki 卡片'
                                      : p.basename(controller.file!.path),
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 8),
                                const Text('仅支持 .apkg，导入标准基础卡、填空卡，以及包内图片和音频。'),
                                const SizedBox(height: 20),
                                PressableAction(
                                  label: controller.file == null
                                      ? '选择 .apkg 文件'
                                      : '重新选择文件',
                                  onPressed: controller.busy
                                      ? null
                                      : () => _pick(controller),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          '支持标准旧版与新版 Zstd 压缩 .apkg。导入基础卡、填空卡和媒体，所有卡片从新卡开始；自定义模板可能跳过。牌组包及解压总量上限均为 512 MB。',
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '遇到同名牌组',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        SegmentedButton<bool>(
                          segments: const [
                            ButtonSegment(value: false, label: Text('建立副本')),
                            ButtonSegment(value: true, label: Text('合并追加')),
                          ],
                          selected: {controller.merge},
                          onSelectionChanged: controller.busy
                              ? null
                              : (s) => controller.setMerge(s.single),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          controller.merge
                              ? '只追加卡片，不覆盖原卡片；重复导入会产生重复卡片。'
                              : '原牌组保持不变，导入副本会自动加上后缀。',
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          '学习进度重新开始',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        const Text('不导入 Anki 的复习进度与排程，所有导入卡片都作为新卡。'),
                        const SizedBox(height: 24),
                        if (controller.error != null) ...[
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              controller.error!,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (controller.busy) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              controller.cancelRequested
                                  ? '正在取消，请等待当前阶段结束…'
                                  : controller.progress?.label ?? '准备导入…',
                            ),
                          ),
                          if (controller.progress?.total != null &&
                              !controller.cancelRequested)
                            Text(
                              '${controller.progress!.completed} / ${controller.progress!.total}',
                            ),
                          const SizedBox(height: 8),
                          const Text('保持应用打开。解析阶段的取消会在当前步骤结束后完成。'),
                          const SizedBox(height: 16),
                          PressableAction(
                            label: controller.cancelRequested ? '等待回滚' : '取消导入',
                            onPressed: controller.cancelRequested
                                ? null
                                : controller.cancel,
                          ),
                        ] else
                          PressableAction(
                            label: controller.error == null ? '确认并导入' : '重新导入',
                            onPressed: controller.file == null
                                ? null
                                : controller.start,
                          ),
                      ],
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
