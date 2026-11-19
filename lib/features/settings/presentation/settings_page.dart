import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/touhou_tag.dart';
import '../../../core/widgets/lunar_widgets.dart';
import 'repository_link_card.dart';

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

    void go(String path) {
      unawaited(FeedbackScope.of(context).tap());
      context.push(path);
    }

    Widget entry(
      String title,
      IconData icon,
      String path, [
      String? subtitle,
    ]) => ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      leading: Icon(icon, size: 22),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right, size: 18),
      onTap: () => go(path),
    );
    Widget group(String label, List<Widget> entries) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        Card(child: Column(children: entries)),
      ],
    );
    return PageFrame(
      title: '我的',
      header: const TouhouTag(TouhouPlace.eientei),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Image.asset(
                      'assets/branding/app-logo.png',
                      width: 62,
                      height: 62,
                      excludeFromSemantics: true,
                    ),
                  ),
                  const SizedBox(width: 15),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lunar Memory',
                          style: TextStyle(fontFamily: 'serif', fontSize: 23),
                        ),
                        SizedBox(height: 7),
                        Text('记忆有处，温习有时'),
                        SizedBox(height: 5),
                        Text('本机学习空间', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          LunarPair(
            first: LunarShortcut(
              label: '我的收藏',
              hint: '留待重读',
              icon: Icons.bookmark_border,
              onTap: () => go('/favorites'),
            ),
            second: LunarShortcut(
              label: '错题列表',
              hint: '拾遗补缺',
              icon: Icons.fact_check_outlined,
              onTap: () => go('/wrong-questions'),
              warm: true,
            ),
          ),
          const SizedBox(height: 18),
          group('学习与阅读', [
            entry('学习设置', Icons.tune_outlined, '/study-settings', '每日额度与记忆排程'),
            entry('字体大小', Icons.text_fields, '/font-settings', '分别调整界面与卡片字号'),
            entry(
              '学习提醒',
              Icons.notifications_outlined,
              '/reminders',
              '每日时间与通知权限',
            ),
          ]),
          const SizedBox(height: 16),
          group('外观与触觉', [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey('theme-${settings['theme'] ?? 'system'}'),
                    initialValue: settings['theme'] ?? 'system',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '外观'),
                    items: const [
                      DropdownMenuItem(value: 'system', child: Text('跟随系统')),
                      DropdownMenuItem(value: 'light', child: Text('浅色')),
                      DropdownMenuItem(value: 'dark', child: Text('深色')),
                    ],
                    onChanged: (value) {
                      if (value != null) save('theme', value);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey(
                      'feedback-${settings['feedback'] ?? 'strong'}',
                    ),
                    initialValue: settings['feedback'] ?? 'strong',
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '触觉反馈'),
                    items: const [
                      DropdownMenuItem(value: 'strong', child: Text('明显')),
                      DropdownMenuItem(value: 'gentle', child: Text('轻柔')),
                      DropdownMenuItem(value: 'off', child: Text('关闭')),
                    ],
                    onChanged: (value) {
                      if (value != null) save('feedback', value);
                    },
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 16),
          group('数据与设备', [
            entry('存储管理', Icons.storage_outlined, '/storage', '空间占用与媒体整理'),
            entry('备份与恢复', Icons.save_outlined, '/backup', '牌组、媒体、进度与刷题记录'),
          ]),
          const SizedBox(height: 16),
          group('关于与反馈', [entry('问题反馈', Icons.mail_outline, '/feedback')]),
          const SizedBox(height: 12),
          const RepositoryLinkCard(),
          const SizedBox(height: 14),
          const Text(
            '本地数据 · 无需登录\n离线导入与学习，数据保存在本机',
            style: TextStyle(fontSize: 12, height: 1.6),
          ),
        ],
      ),
    );
  }
}
