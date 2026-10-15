import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/page_frame.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? {};
    Future<void> save(String key, String value) async {
      try {
        await saveSetting(ref, key, value);
      } catch (error) {
        if (context.mounted) showActionError(context, error);
      }
    }

    return PageFrame(
      title: '我的',
      subtitle: '按你的习惯，安排每一次学习。',
      child: Column(
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.tune_outlined),
                  title: const Text('学习设置'),
                  subtitle: const Text('每日额度与 FSRS 期望保持率'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/study-settings'),
                ),
                ListTile(
                  title: const Text('外观'),
                  subtitle: const Text('浅色、深色或跟随系统'),
                  trailing: DropdownButton<String>(
                    value: settings['theme'] ?? 'system',
                    items: const [
                      DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                      DropdownMenuItem(value: 'light', child: Text('浅色')),
                      DropdownMenuItem(value: 'dark', child: Text('深色')),
                    ],
                    onChanged: (value) {
                      if (value != null) save('theme', value);
                    },
                  ),
                ),
                ListTile(
                  title: const Text('触觉反馈'),
                  subtitle: const Text('按键确认的震动强度'),
                  trailing: DropdownButton<String>(
                    value: settings['feedback'] ?? 'strong',
                    items: const [
                      DropdownMenuItem(value: 'strong', child: Text('明显')),
                      DropdownMenuItem(value: 'gentle', child: Text('轻柔')),
                      DropdownMenuItem(value: 'off', child: Text('关闭')),
                    ],
                    onChanged: (value) {
                      if (value != null) save('feedback', value);
                    },
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.storage_outlined),
                  title: const Text('存储管理'),
                  subtitle: const Text('空间占用与未使用媒体清理'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/storage'),
                ),
                const ListTile(
                  title: Text('本地数据'),
                  subtitle: Text('数据库只保存在本机，无需登录'),
                ),
                ListTile(
                  leading: const Icon(Icons.notifications_outlined),
                  title: const Text('学习提醒'),
                  subtitle: const Text('每日时间与系统通知权限'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/reminders'),
                ),
                ListTile(
                  leading: const Icon(Icons.save_outlined),
                  title: const Text('备份与恢复'),
                  subtitle: const Text('保存卡片、媒体和学习进度'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/backup'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const ListTile(
            title: Text('Lunar Memory · 开发版'),
            subtitle: Text('离线导入与学习，本机保存全部数据。增强功能持续完善中。'),
          ),
        ],
      ),
    );
  }
}
