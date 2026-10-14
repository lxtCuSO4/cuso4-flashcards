import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider);
    final counts = ref.watch(cardCountsProvider).value ?? {};
    final total = counts.values.fold<int>(0, (sum, count) => sum + count);
    final scheme = Theme.of(context).colorScheme;
    return PageFrame(
      title: 'CuSO₄闪卡',
      subtitle: '今天，也为记忆留一点时间。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '你的知识库',
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: scheme.onPrimary),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '$total',
                    style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '张卡片 · 保存在本机',
                    style: TextStyle(color: scheme.onPrimary),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.tonal(
                    onPressed: () => context.go('/decks'),
                    child: const Text('整理我的牌组'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          PressableAction(
            label: '开始今日学习',
            onPressed: total == 0 ? null : () => context.push('/study'),
          ),
          const SizedBox(height: 24),
          Text('牌组概览', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          decks.when(
            data: (items) => items.isEmpty
                ? const ListTile(title: Text('还没有牌组'))
                : Column(
                    children: items
                        .map(
                          (item) => ListTile(
                            leading: const Icon(Icons.layers_outlined),
                            title: Text(item.name),
                            subtitle: Text('${counts[item.id] ?? 0} 张卡片'),
                            onTap: () => context.push('/decks/${item.id}'),
                            trailing: const Icon(Icons.chevron_right),
                          ),
                        )
                        .toList(),
                  ),
            loading: () => const LinearProgressIndicator(),
            error: (e, _) => const Text('牌组加载失败，请重新打开应用。'),
          ),
        ],
      ),
    );
  }
}
