import 'package:flutter/material.dart';

class PageFrame extends StatelessWidget {
  const PageFrame({
    super.key,
    required this.title,
    required this.child,
    this.titleLeading,
    this.subtitle,
    this.header,
    this.actions = const [],
    this.scrollController,
  });
  final String title;
  final Widget? titleLeading;
  final String? subtitle;
  final Widget? header;
  final Widget child;
  final List<Widget> actions;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: titleLeading == null
          ? Text(title)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                titleLeading!,
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
      actions: actions,
    ),
    body: SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ?header,
                if (subtitle != null) ...[
                  Text(
                    subtitle!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
                child,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

void showActionError(BuildContext context, Object error) {
  final message = error is ArgumentError
      ? '${error.message}'
      : error is StateError
      ? error.message
      : '操作未完成，请重试。';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirmRemoval(
  BuildContext context,
  String message, {
  String title = '确认删除',
  String confirmLabel = '删除',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    ) ??
    false;

Future<String?> requestName(
  BuildContext context,
  String title, {
  String initial = '',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 255,
        decoration: const InputDecoration(labelText: '牌组名称'),
        onSubmitted: (value) => Navigator.pop(dialogContext, value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: const Text('保存'),
        ),
      ],
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 250));
  controller.dispose();
  return result;
}
