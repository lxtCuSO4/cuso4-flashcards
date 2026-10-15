import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/touhou_tag.dart';
import '../../../core/widgets/pressable_action.dart';
import '../../decks/domain/note.dart';
import '../data/favorite_repository.dart';
import 'favorite_deck_filter.dart';

typedef FavoritesQuery = ({int offset, int? deckId, bool includeChildren});

final favoritesPageProvider = StreamProvider.autoDispose.family(
  (ref, FavoritesQuery query) =>
      FavoriteRepository(ref.watch(databaseProvider)).watchPage(
        offset: query.offset,
        deckId: query.deckId,
        includeChildren: query.includeChildren,
      ),
);

class FavoritesPage extends ConsumerStatefulWidget {
  const FavoritesPage({super.key});
  @override
  ConsumerState<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends ConsumerState<FavoritesPage> {
  int _offset = 0;
  int? _deckId;
  bool _includeChildren = true;
  final _removing = <int>{};

  Future<void> _remove(int cardId) async {
    if (!_removing.add(cardId)) return;
    setState(() {});
    final feedback = FeedbackScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    unawaited(feedback.tap());
    final repository = ref.read(studyRepositoryProvider);
    try {
      await repository.setFavorite(cardId, false);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: const Text('已取消收藏'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () async {
              unawaited(feedback.tap());
              try {
                await repository.setFavorite(cardId, true);
              } catch (_) {
                if (messenger.mounted) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('卡片已删除或暂时无法恢复收藏，请重新查看收藏列表。')),
                  );
                }
              }
            },
          ),
        ),
      );
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      if (mounted) setState(() => _removing.remove(cardId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = (
      offset: _offset,
      deckId: _deckId,
      includeChildren: _includeChildren,
    );
    final result = ref.watch(favoritesPageProvider(query));
    final decks = ref.watch(decksProvider);
    final missingDeck =
        _deckId != null &&
        decks.hasValue &&
        !decks.value!.any((d) => d.id == _deckId);
    return PageFrame(
      title: '我的收藏',
      header: const TouhouTag(TouhouPlace.bookmarks),
      subtitle: '把需要再想一想的知识留在这里。预览不会改变学习进度。',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          decks.when(
            data: (items) => Container(
              key: const ValueKey('favorite-deck-filter'),
              child: FavoriteDeckFilter(
                decks: items,
                deckId: _deckId,
                onChanged: (id) {
                  unawaited(FeedbackScope.of(context).tap());
                  setState(() {
                    _deckId = id;
                    _offset = 0;
                  });
                },
              ),
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('牌组范围加载失败。'),
                PressableAction(
                  label: '重新加载牌组',
                  onPressed: () => ref.invalidate(decksProvider),
                ),
              ],
            ),
          ),
          if (_deckId != null) ...[
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('包含子章节'),
              subtitle: const Text('同时查看这个牌组下各级章节的收藏'),
              value: _includeChildren,
              onChanged: (value) {
                unawaited(FeedbackScope.of(context).tap());
                setState(() {
                  _includeChildren = value;
                  _offset = 0;
                });
              },
            ),
          ],
          const SizedBox(height: 24),
          result.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => Column(
              children: [
                const Text('收藏加载失败，请重试。'),
                const SizedBox(height: 16),
                PressableAction(
                  label: '重新加载收藏',
                  onPressed: () => ref.invalidate(favoritesPageProvider(query)),
                ),
              ],
            ),
            data: (page) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PressableAction(
                  label: '收藏随机练习',
                  onPressed: missingDeck || (page.items.isEmpty && _offset == 0)
                      ? null
                      : () => context.push(
                          Uri(
                            path: '/favorite-practice',
                            queryParameters: {
                              if (_deckId != null) 'deckId': '$_deckId',
                              'children': '$_includeChildren',
                            },
                          ).toString(),
                        ),
                ),
                const SizedBox(height: 12),
                const Text('按当前范围的全部收藏抽卡，不限本页；不改变学习进度和统计。'),
                const SizedBox(height: 16),
                if (page.items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.bookmark_border,
                          size: 48,
                          color: Theme.of(context).colorScheme.secondary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _offset > 0
                              ? '本页暂无收藏'
                              : _deckId == null
                              ? '还没有收藏卡片'
                              : '当前范围没有收藏卡片',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _offset > 0
                              ? '可以返回上一页继续查看。'
                              : _deckId == null
                              ? '学习时点击书签，即可在这里集中回看。'
                              : '可切换牌组、包含子章节，或在学习时收藏卡片。',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                for (final entry in page.items)
                  Card(
                    elevation: 0,
                    child: ListTile(
                      key: ValueKey('favorite-card-${entry.cardId}'),
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      title: Text(
                        entry.preview,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${entry.deckName} · ${entry.type == NoteType.cloze ? '填空 c${entry.clozeIndex}' : entry.type.label}',
                      ),
                      trailing: IconButton(
                        tooltip: '取消收藏',
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        onPressed: _removing.contains(entry.cardId)
                            ? null
                            : () => _remove(entry.cardId),
                        icon: const Icon(Icons.bookmark),
                      ),
                      onTap: () {
                        unawaited(FeedbackScope.of(context).tap());
                        context.push('/favorites/${entry.cardId}');
                      },
                    ),
                  ),
                if (_offset > 0 || page.hasNext) ...[
                  const SizedBox(height: 24),
                  Text('第 ${_offset ~/ 30 + 1} 页', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 16,
                    runSpacing: 12,
                    children: [
                      PressableAction(
                        label: '上一页',
                        onPressed: _offset == 0
                            ? null
                            : () => setState(() => _offset -= 30),
                      ),
                      PressableAction(
                        label: '下一页',
                        onPressed: !page.hasNext
                            ? null
                            : () => setState(() => _offset += 30),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
