import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';

final deckNotesProvider = StreamProvider.autoDispose.family((ref, int deckId) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.notes)..where((n) => n.deckId.equals(deckId))).watch();
});

class CardListPage extends ConsumerStatefulWidget {
  const CardListPage({super.key, required this.deckId});
  final int deckId;
  @override
  ConsumerState<CardListPage> createState() => _CardListPageState();
}

class _CardListPageState extends ConsumerState<CardListPage> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final name =
        ref
            .watch(decksProvider)
            .value
            ?.where((d) => d.id == widget.deckId)
            .firstOrNull
            ?.name ??
        '卡片';
    final notes = ref.watch(deckNotesProvider(widget.deckId));
    return PageFrame(
      title: name,
      actions: [
        IconButton(
          onPressed: () => context.push('/search?deckId=${widget.deckId}'),
          icon: const Icon(Icons.checklist_outlined),
          tooltip: '搜索与批量管理',
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PressableAction(
            label: '学习这个牌组',
            onPressed: () => context.push('/study?deckId=${widget.deckId}'),
          ),
          const SizedBox(height: 12),
          PressableAction(
            label: '随机练习',
            onPressed: () => context.push('/practice/${widget.deckId}'),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索卡片内容',
            ),
            onChanged: (value) => setState(() => _query = value.toLowerCase()),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: PressableAction(
              label: '新建卡片',
              onPressed: () => context.push('/decks/${widget.deckId}/new'),
            ),
          ),
          const SizedBox(height: 24),
          notes.when(
            data: (items) {
              final filtered = items
                  .where((n) => n.fieldsJson.toLowerCase().contains(_query))
                  .toList();
              if (filtered.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    '暂无卡片。添加一张基础卡或填空卡吧。',
                    textAlign: TextAlign.center,
                  ),
                );
              }
              return Column(
                children: filtered.map((note) {
                  final fields = Map<String, String>.from(
                    jsonDecode(note.fieldsJson) as Map,
                  );
                  return Card(
                    elevation: 0,
                    child: ListTile(
                      title: Text(
                        fields['front'] ?? fields['text'] ?? '',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(note.noteType == 0 ? '基础卡' : '填空卡'),
                      onTap: () => context.push(
                        '/decks/${widget.deckId}/edit/${note.id}',
                      ),
                      trailing: IconButton(
                        tooltip: '删除卡片',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (!await confirmRemoval(
                            context,
                            '删除这条笔记及其生成的卡片和学习记录？',
                          )) {
                            return;
                          }
                          try {
                            final repository = ref.read(noteRepositoryProvider);
                            await repository.deleteNote(note.id);
                            unawaited(cleanUpUnusedMedia(repository.media));
                          } catch (e) {
                            if (context.mounted) showActionError(context, e);
                          }
                        },
                      ),
                    ),
                  );
                }).toList(),
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('卡片加载失败。'),
          ),
        ],
      ),
    );
  }
}
