import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/widgets/page_frame.dart';
import '../../core/widgets/pressable_action.dart';
import '../backup/presentation/backup_page.dart';
import 'storage_repository.dart';

final storageRepositoryProvider = Provider(
  (ref) => StorageRepository(
    ref.watch(databaseProvider),
    ref.watch(mediaRepositoryProvider),
  ),
);

class StoragePage extends ConsumerStatefulWidget {
  const StoragePage({super.key});
  @override
  ConsumerState<StoragePage> createState() => _StoragePageState();
}

class _StoragePageState extends ConsumerState<StoragePage> {
  StorageSummary? _summary;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  String _size(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MiB';
  Future<void> _refresh() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final summary = await ref.read(storageRepositoryProvider).inspect();
      if (mounted) setState(() => _summary = summary);
    } catch (_) {
      if (mounted) setState(() => _error = '存储统计失败，请重试。');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clean() async {
    if (_busy) return;
    if (ref.read(importControllerProvider).busy ||
        ref.read(backupControllerProvider).busy) {
      showActionError(context, StateError('请等待导入、备份或恢复结束后再清理。'));
      return;
    }
    if (!await confirmRemoval(
      context,
      '清理未被任何笔记引用的本地媒体？执行前会重新检查引用，保留卡片使用的图片、备份和学习进度。',
      title: '确认清理',
      confirmLabel: '清理',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final result = await ref.read(storageRepositoryProvider).clean();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '清理 ${result.files} 个文件，释放 ${_size(result.bytes)}${result.failed == 0 ? '' : '，${result.failed} 个暂时无法清理'}',
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      if (mounted) await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    return PopScope(
      canPop: !_busy,
      child: PageFrame(
        title: '存储管理',
        subtitle: '查看本机数据占用，按需要清理未使用的媒体。',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_busy) const LinearProgressIndicator(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(_error!),
              ),
            if (summary != null) ...[
              ListTile(
                title: const Text('数据库与日志文件'),
                subtitle: Text(_size(summary.databaseBytes)),
              ),
              ListTile(
                title: const Text('本地媒体'),
                subtitle: Text(_size(summary.mediaBytes)),
              ),
              ListTile(
                title: const Text('可清理媒体'),
                subtitle: Text(
                  '${summary.unusedCount} 个文件 · ${_size(summary.unusedBytes)}',
                ),
              ),
              if (summary.missingCount > 0)
                ListTile(
                  title: const Text('需要检查的媒体'),
                  subtitle: Text(
                    '${summary.missingCount} 项引用缺失或大小异常；请检查相应卡片或恢复完整备份。',
                  ),
                ),
              const SizedBox(height: 24),
              PressableAction(
                label: '清理未使用媒体',
                onPressed: _busy || summary.unusedCount == 0 ? null : _clean,
              ),
            ],
            const SizedBox(height: 16),
            PressableAction(label: '刷新统计', onPressed: _busy ? null : _refresh),
            const SizedBox(height: 24),
            const Text(
              '统计不包括应用安装包和你保存在其他位置的牌组／备份。清理仅处理应用媒体目录内确认无引用的哈希文件；未知文件、目录和符号链接不会删除。',
            ),
          ],
        ),
      ),
    );
  }
}
