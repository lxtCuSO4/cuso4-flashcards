import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/feedback/feedback_controller.dart';

class RepositoryLinkCard extends StatefulWidget {
  const RepositoryLinkCard({super.key});
  @override
  State<RepositoryLinkCard> createState() => _RepositoryLinkCardState();
}

class _RepositoryLinkCardState extends State<RepositoryLinkCard> {
  static const _url = 'https://github.com/lxtCuSO4/cuso4-flashcards';
  static const _channel = MethodChannel('com.cuso4.flashcards/repository_link');
  bool _busy = false;
  bool _failed = false;

  Future<void> _open() async {
    if (_busy) return;
    unawaited(FeedbackScope.of(context).tap());
    setState(() {
      _busy = true;
      _failed = false;
    });
    var opened = false;
    try {
      opened = await _channel.invokeMethod<bool>('openRepository') ?? false;
    } catch (_) {
      // Offline app functionality remains available without an external browser.
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _failed = !opened;
        });
      }
    }
  }

  Future<void> _copy() async {
    unawaited(FeedbackScope.of(context).tap());
    try {
      await Clipboard.setData(const ClipboardData(text: _url));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已复制仓库链接')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('复制失败，可以长按下方链接手动复制。')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          contentPadding: const EdgeInsets.all(16),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/branding/github-meme.png',
              width: 56,
              height: 56,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
          title: const Text('GitHub 仓库'),
          subtitle: const Text('lxtCuSO4 / cuso4-flashcards\n用系统浏览器查看，需要网络'),
          isThreeLine: true,
          trailing: _busy
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    semanticsLabel: '正在打开仓库',
                  ),
                )
              : const Icon(Icons.open_in_new),
          onTap: _busy ? null : _open,
        ),
        if (_failed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  liveRegion: true,
                  child: const Text('未能打开浏览器，可以复制链接后自行打开。'),
                ),
                const SizedBox(height: 8),
                const SelectableText(_url),
                TextButton.icon(
                  onPressed: _copy,
                  icon: const Icon(Icons.copy_outlined),
                  label: const Text('复制仓库链接'),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
