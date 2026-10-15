import 'dart:async';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/feedback/feedback_controller.dart';
import '../../../core/widgets/page_frame.dart';
import '../../../core/widgets/pressable_action.dart';
import '../../decks/domain/note.dart';
import '../../decks/domain/choice_question.dart';
import '../../decks/presentation/note_preview_page.dart';
import '../../favorites/presentation/favorite_deck_filter.dart';
import '../data/search_repository.dart';

final searchRepositoryProvider = Provider(
  (ref) => SearchRepository(
    ref.watch(databaseProvider),
    ref.watch(noteRepositoryProvider),
  ),
);
final searchResultsProvider = StreamProvider.autoDispose.family(
  (ref, SearchQuery query) => ref.watch(searchRepositoryProvider).watch(query),
);
final searchTagsProvider = StreamProvider.autoDispose(
  (ref) =>
      (ref.watch(databaseProvider).select(ref.watch(databaseProvider).tags)
            ..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch(),
);

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, this.deckId});
  final int? deckId;
  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _text = TextEditingController();
  Timer? _debounce;
  late int? _deck = widget.deckId;
  String _query = '';
  String? _tag;
  int? _type;
  bool _children = true, _favorites = false, _working = false;
  bool _applying = false;
  int _offset = 0;
  final _selected = <int>{};
  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _change(VoidCallback update) {
    setState(() {
      update();
      _offset = 0;
      _selected.clear();
    });
  }

  Future<void> _preview(SearchItem item) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => NotePreviewPage(
        type: NoteType.values[item.noteType],
        choice: NoteType.values[item.noteType].isChoice
            ? ChoiceQuestion.fromFields(
                NoteType.values[item.noteType],
                item.fields,
              )
            : null,
        front: item.fields['front'] ?? item.fields['text'] ?? '',
        back: item.fields['back'] ?? item.fields['extra'] ?? '',
        media: ref.read(mediaRepositoryProvider),
        draftImages: const {},
      ),
    ),
  );

  Future<void> _batch(BatchAction action) async {
    if (_working || _selected.isEmpty || _text.text != _query) return;
    unawaited(FeedbackScope.of(context).tap());
    final ids = Set<int>.of(_selected);
    setState(() => _working = true);
    try {
      int? target;
      String? tagText;
      if (action == BatchAction.delete) {
        if (!await confirmRemoval(
          context,
          '永久删除选中的 ${ids.length} 条笔记及其生成的全部卡片、收藏和学习记录？此操作无法撤销。',
        )) {
          return;
        }
      } else if (action == BatchAction.move) {
        final decks = ref.read(decksProvider).value;
        if (decks == null || decks.isEmpty) throw StateError('请先创建目标牌组。');
        target = await showDialog<int>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
              title: const Text('移动到牌组'),
              content: SizedBox(
                width: 400,
                child: FavoriteDeckFilter(
                  decks: decks,
                  deckId: target,
                  onChanged: (v) => update(() => target = v),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                TextButton(
                  onPressed: target == null
                      ? null
                      : () => Navigator.pop(dialogContext, target),
                  child: const Text('移动'),
                ),
              ],
            ),
          ),
        );
        if (target == null) return;
      } else {
        tagText = await showDialog<String>(
          context: context,
          builder: (_) => _TagDialog(add: action == BatchAction.addTags),
        );
        if (tagText == null) return;
      }
      setState(() => _applying = true);
      await ref
          .read(searchRepositoryProvider)
          .applyBatch(
            ids,
            action: action,
            deckId: target,
            tags: tagText?.split(RegExp(r'[\s,，]+')) ?? const [],
          );
      if (action == BatchAction.delete) {
        await cleanUpUnusedMedia(ref.read(mediaRepositoryProvider));
      }
      if (mounted) {
        setState(() => _selected.clear());
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已处理 ${ids.length} 条笔记')));
      }
    } catch (error) {
      if (mounted) showActionError(context, error);
    } finally {
      if (mounted) {
        setState(() {
          _working = false;
          _applying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(
      searchResultsProvider((
        text: _query,
        deckId: _deck,
        includeChildren: _children,
        noteType: _type,
        tag: _tag,
        favoritesOnly: _favorites,
        offset: _offset,
      )),
    );
    final decks = ref.watch(decksProvider);
    final tags = ref.watch(searchTagsProvider).value ?? [];
    return PopScope(
      canPop: !_working,
      child: PageFrame(
        title: '搜索与批量管理',
        subtitle: '跨牌组查找笔记。批量操作会影响笔记生成的全部卡片。',
        child: AbsorbPointer(
          absorbing: _working,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_applying) const LinearProgressIndicator(),
              TextField(
                controller: _text,
                decoration: const InputDecoration(
                  labelText: '搜索内容',
                  hintText: '输入正面、答案或来源文字',
                  prefixIcon: Icon(Icons.search),
                ),
                onChanged: (value) {
                  _debounce?.cancel();
                  setState(_selected.clear);
                  _debounce = Timer(const Duration(milliseconds: 300), () {
                    if (mounted) _change(() => _query = value);
                  });
                },
              ),
              const SizedBox(height: 16),
              decks.when(
                data: (value) => FavoriteDeckFilter(
                  decks: value,
                  deckId: _deck,
                  onChanged: (v) => _change(() => _deck = v),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('牌组读取失败，请返回后重试。'),
              ),
              if (_deck != null)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('包含子章节'),
                  value: _children,
                  onChanged: (v) => _change(() => _children = v ?? true),
                ),
              const SizedBox(height: 16),
              DropdownButtonFormField<int>(
                initialValue: -1,
                decoration: const InputDecoration(labelText: '卡片类型'),
                items: const [
                  DropdownMenuItem(value: -1, child: Text('全部类型')),
                  DropdownMenuItem(value: 0, child: Text('基础卡')),
                  DropdownMenuItem(value: 1, child: Text('填空卡')),
                  DropdownMenuItem(value: 2, child: Text('单选题')),
                  DropdownMenuItem(value: 3, child: Text('多选题')),
                ],
                onChanged: (v) => _change(() => _type = v == -1 ? null : v),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('tag-$_tag-${tags.length}'),
                initialValue: _tag ?? '',
                isExpanded: true,
                decoration: const InputDecoration(labelText: '标签'),
                items: [
                  const DropdownMenuItem(value: '', child: Text('全部标签')),
                  if (_tag != null && !tags.any((t) => t.name == _tag))
                    DropdownMenuItem(value: _tag, child: Text('$_tag（已无标签）')),
                  for (final tag in tags)
                    DropdownMenuItem(
                      value: tag.name,
                      child: Text(tag.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) => _change(() => _tag = v == '' ? null : v),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('仅看收藏笔记'),
                subtitle: const Text('任一卡片已收藏即包含该笔记'),
                value: _favorites,
                onChanged: (v) => _change(() => _favorites = v ?? false),
              ),
              const SizedBox(height: 16),
              Text(
                '已选 ${_selected.length} 条笔记（仅当前页）',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in BatchAction.values)
                    OutlinedButton(
                      onPressed: _selected.isEmpty || _text.text != _query
                          ? null
                          : () => _batch(action),
                      child: Text(switch (action) {
                        BatchAction.move => '移动',
                        BatchAction.addTags => '添加标签',
                        BatchAction.removeTags => '移除标签',
                        BatchAction.delete => '删除',
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              result.when(
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => PressableAction(
                  label: '搜索失败，点击重试',
                  onPressed: () => ref.invalidate(searchResultsProvider),
                ),
                data: (page) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (page.items.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('没有匹配的笔记，请调整搜索或筛选。'),
                      ),
                    if (page.items.isNotEmpty)
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('全选本页'),
                        value: page.items.every(
                          (n) => _selected.contains(n.id),
                        ),
                        onChanged: _text.text != _query
                            ? null
                            : (v) => setState(() {
                                _selected.clear();
                                if (v == true) {
                                  _selected.addAll(page.items.map((n) => n.id));
                                }
                              }),
                      ),
                    for (final item in page.items)
                      Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            children: [
                              CheckboxListTile(
                                value: _selected.contains(item.id),
                                onChanged: _text.text != _query
                                    ? null
                                    : (v) => setState(() {
                                        v == true
                                            ? _selected.add(item.id)
                                            : _selected.remove(item.id);
                                      }),
                                title: Text(
                                  item.summary,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${item.deckPath}\n${NoteType.values[item.noteType].label} · ${item.cardCount} 张卡片',
                                ),
                              ),
                              Wrap(
                                spacing: 16,
                                children: [
                                  TextButton(
                                    onPressed: () => _preview(item),
                                    child: const Text('预览'),
                                  ),
                                  TextButton(
                                    onPressed: () => context.push(
                                      '/decks/${item.deckId}/edit/${item.id}',
                                    ),
                                    child: const Text('编辑'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    Text(
                      '第 ${_offset ~/ 30 + 1} 页 · 本页 ${page.items.length} 条笔记',
                    ),
                    Wrap(
                      spacing: 16,
                      children: [
                        TextButton(
                          onPressed: _offset == 0
                              ? null
                              : () => setState(() {
                                  _offset -= 30;
                                  _selected.clear();
                                }),
                          child: const Text('上一页'),
                        ),
                        TextButton(
                          onPressed: !page.hasNext
                              ? null
                              : () => setState(() {
                                  _offset += 30;
                                  _selected.clear();
                                }),
                          child: const Text('下一页'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagDialog extends StatefulWidget {
  const _TagDialog({required this.add});
  final bool add;
  @override
  State<_TagDialog> createState() => _TagDialogState();
}

class _TagDialogState extends State<_TagDialog> {
  final _controller = TextEditingController();
  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.add ? '批量添加标签' : '批量移除标签'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: 1000,
      decoration: const InputDecoration(
        labelText: '标签',
        helperText: '多个标签用空格或逗号分隔',
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _controller.text),
        child: const Text('确认'),
      ),
    ],
  );
}
