import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';

class RecordsPage extends StatelessWidget {
  const RecordsPage({super.key});
  @override
  Widget build(BuildContext context) => PageFrame(
    title: '记录',
    subtitle: '回看需要巩固的知识，慢慢积累。',
    child: Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              Icons.bookmark_border,
              size: 40,
              color: Theme.of(context).colorScheme.secondary,
            ),
            const SizedBox(height: 16),
            Text('我的收藏', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('学习时留下书签，在这里集中预览。预览不会改变 FSRS 排程。'),
            const SizedBox(height: 24),
            PressableAction(
              label: '查看收藏',
              onPressed: () => context.push('/favorites'),
            ),
          ],
        ),
      ),
    ),
  );
}
