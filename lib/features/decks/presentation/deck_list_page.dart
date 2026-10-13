import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/database/app_database.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';

class DeckListPage extends ConsumerWidget {
  const DeckListPage({super.key});
  Future<void> _action(
    BuildContext context,
    WidgetRef ref,
    String value,
    StoredDeck deck,
    List<StoredDeck> items,
  ) async {
    final repository = ref.read(deckRepositoryProvider);
    try {
      switch (value) {
        case 'rename':
          final name = await requestName(context, '重命名牌组', initial: deck.name);
          if (name != null) await repository.renameDeck(deck.id, name);
        case 'child':
          final name = await requestName(context, '新建子牌组');
          if (name != null) {
            await repository.createDeck(name, parentId: deck.id);
          }
        case 'move':
          final parent = await showDialog<int>(
            context: context,
            builder: (dialogContext) => SimpleDialog(
              title: const Text('移动到'),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, 0),
                  child: const Text('顶层'),
                ),
                ...items
                    .where((d) => d.id != deck.id)
                    .map(
                      (d) => SimpleDialogOption(
                        onPressed: () => Navigator.pop(dialogContext, d.id),
                        child: Text(d.name),
                      ),
                    ),
              ],
            ),
          );
          if (parent != null) {
            await repository.moveDeck(deck.id, parent == 0 ? null : parent);
          }
        case 'delete':
          if (await confirmRemoval(
            context,
            '删除“${deck.name}”及其子牌组、全部卡片和学习记录？此操作无法撤销。',
          )) {
            await repository.deleteDeck(deck.id);
          }
      }
    } catch (error) {
      if (context.mounted) showActionError(context, error);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final decks = ref.watch(decksProvider);
    final counts = ref.watch(cardCountsProvider).value ?? {};
    return PageFrame(
      title: '牌组',
      subtitle: '把知识整理成小块，慢慢记牢。',
      actions: [
        IconButton(
          onPressed: () => _importNotice(context),
          icon: const Icon(Icons.file_download_outlined),
          tooltip: '导入 .apkg',
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: PressableAction(
              label: '新建牌组',
              onPressed: () async {
                final name = await requestName(context, '新建牌组');
                if (name == null) return;
                try {
                  await ref.read(deckRepositoryProvider).createDeck(name);
                } catch (e) {
                  if (context.mounted) showActionError(context, e);
                }
              },
            ),
          ),
          const SizedBox(height: 24),
          decks.when(
            data: (items) {
              if (items.isEmpty) {
                return Card(
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(
                          Icons.style_outlined,
                          size: 52,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          '从一个牌组开始',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '创建自己的卡片，整理值得记住的知识。',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        PressableAction(
                          label: '导入 .apkg',
                          onPressed: () => _importNotice(context),
                        ),
                      ],
                    ),
                  ),
                );
              }
              final ordered = <({StoredDeck deck, int depth})>[];
              void append(int? parent, int depth) {
                for (final d in items.where((d) => d.parentId == parent)) {
                  ordered.add((deck: d, depth: depth));
                  append(d.id, depth + 1);
                }
              }

              append(null, 0);
              return Column(
                children: ordered
                    .map(
                      (entry) => Padding(
                        padding: EdgeInsets.only(
                          left: (entry.depth * 16.0).clamp(0, 48),
                          bottom: 10,
                        ),
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 0,
                          child: ListTile(
                            contentPadding: const EdgeInsets.only(
                              left: 20,
                              right: 8,
                              top: 10,
                              bottom: 10,
                            ),
                            leading: Icon(
                              Icons.layers_outlined,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                            title: Text(
                              entry.deck.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text('${counts[entry.deck.id] ?? 0} 张卡片'),
                            onTap: () =>
                                context.push('/decks/${entry.deck.id}'),
                            trailing: PopupMenuButton<String>(
                              tooltip: '牌组操作',
                              onSelected: (value) => _action(
                                context,
                                ref,
                                value,
                                entry.deck,
                                items,
                              ),
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'rename',
                                  child: Text('重命名'),
                                ),
                                PopupMenuItem(
                                  value: 'child',
                                  child: Text('新建子牌组'),
                                ),
                                PopupMenuItem(
                                  value: 'move',
                                  child: Text('移动牌组'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Text('删除牌组'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('牌组加载失败，请重新打开应用。'),
          ),
        ],
      ),
    );
  }

  void _importNotice(BuildContext context) => ScaffoldMessenger.of(context)
      .showSnackBar(
        const SnackBar(content: Text('.apkg 导入将在下一开发阶段接入。当前可创建本地卡片。')),
      );
}
