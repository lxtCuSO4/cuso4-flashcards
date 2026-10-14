import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/pressable_action.dart';
import '../application/backup_controller.dart';
import '../data/backup_platform.dart';

final backupControllerProvider = Provider((ref) {
  final controller = BackupController(
    database: () => ref.read(databaseProvider),
    root: getApplicationSupportDirectory,
    platform: BackupPlatform(),
    importBusy: () => ref.read(importControllerProvider).busy,
    databaseChanged: () => ref.invalidate(databaseProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

class BackupPage extends ConsumerStatefulWidget {
  const BackupPage({super.key});
  @override
  ConsumerState<BackupPage> createState() => _BackupPageState();
}

class _BackupPageState extends ConsumerState<BackupPage> {
  @override
  void initState() {
    super.initState();
    unawaited(
      ref
          .read(backupControllerProvider)
          .refreshRecovery()
          .catchError((Object _) {}),
    );
  }

  Future<bool> _confirmRestore() async =>
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => AlertDialog(
          title: const Text('用备份替换本机数据？'),
          content: const SingleChildScrollView(
            child: Text(
              '这不是追加导入：当前卡片、媒体、收藏、设置和学习进度将被备份中的内容替换。\n\n'
              '恢复前会自动保留当前数据快照；本机仅保留最近一次恢复前的快照，可在此页面导出。\n\n'
              '切换数据时请勿关闭应用。',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('保留当前数据'),
            ),
            PressableAction(
              label: '确认恢复',
              onPressed: () => Navigator.pop(dialog, true),
            ),
          ],
        ),
      ) ??
      false;

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(backupControllerProvider);
    final settings = ref.watch(settingsProvider).value ?? {};
    final time = DateTime.tryParse(settings['lastBackupUtc'] ?? '');
    final bytes = int.tryParse(settings['lastBackupBytes'] ?? '');
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => PopScope(
        canPop: !controller.busy,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('备份与恢复'),
            automaticallyImplyLeading: !controller.busy,
          ),
          body: SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      '让每一次学习，都有备份。',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text('完全离线。备份包含牌组、卡片、图片、收藏、设置和 FSRS 学习进度。'),
                    const SizedBox(height: 24),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '保存完整备份',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              time == null
                                  ? '尚未导出备份'
                                  : '上次导出：${DateFormat('yyyy-MM-dd HH:mm').format(time.toLocal())}',
                            ),
                            if (bytes != null)
                              Text(
                                '上次备份大小：${(bytes / 1024 / 1024).toStringAsFixed(1)} MB',
                              ),
                            const SizedBox(height: 16),
                            PressableAction(
                              label: '导出本地备份',
                              onPressed: controller.busy
                                  ? null
                                  : controller.export,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '选择手机文件夹保存 .cuso4backup 文件。备份未加密，请妥善保管；卸载前务必导出到应用外。',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '从备份恢复',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '恢复会替换本机全部学习数据，不会与现有卡片合并。.apkg 牌组请到“牌组”页导入。',
                            ),
                            const SizedBox(height: 16),
                            PressableAction(
                              label: '选择备份并恢复',
                              onPressed: controller.busy
                                  ? null
                                  : () async {
                                      await controller.restore(
                                        confirm: _confirmRestore,
                                      );
                                      if (!context.mounted ||
                                          !controller.restored) {
                                        return;
                                      }
                                      context.go('/settings');
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            const SnackBar(
                                              content: Text('恢复完成，已保留恢复前快照。'),
                                            ),
                                          );
                                    },
                            ),
                            if (controller.hasRecovery) ...[
                              const SizedBox(height: 16),
                              const Text(
                                '本机已保留最近一次恢复前的数据。可导出后再次选择恢复；该快照仍会随卸载丢失。',
                              ),
                              const SizedBox(height: 12),
                              PressableAction(
                                label: '导出恢复前快照',
                                onPressed: controller.busy
                                    ? null
                                    : () => controller.export(previous: true),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (controller.busy) ...[
                      const SizedBox(height: 24),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      Semantics(
                        liveRegion: true,
                        child: Text(controller.progress ?? '准备中'),
                      ),
                      if (controller.canCancel) ...[
                        const SizedBox(height: 12),
                        PressableAction(
                          label: '取消操作',
                          onPressed: controller.cancel,
                        ),
                        const SizedBox(height: 8),
                        const Text('取消会在当前打包或校验步骤结束后生效。'),
                      ],
                    ],
                    if (controller.error case final error?) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          error,
                          style: TextStyle(color: scheme.error),
                        ),
                      ),
                    ],
                    if (controller.message case final message?) ...[
                      const SizedBox(height: 16),
                      Semantics(liveRegion: true, child: Text(message)),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
