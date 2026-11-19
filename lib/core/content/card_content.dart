import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import '../media/local_audio_controller.dart';
import '../media/media_repository.dart';
import '../widgets/pressable_action.dart';
import '../typography/font_scale_scope.dart';

/// Native rendering ignores CSS, links and executable HTML.
class CardContent extends StatelessWidget {
  const CardContent({
    super.key,
    required this.source,
    required this.media,
    required this.audio,
    this.draftImages = const {},
    this.textScaler,
    this.lineHeight = 1.65,
    this.imageMaxHeight = 280,
    this.zoomImages = false,
  });
  final String source;
  final MediaRepository media;
  final LocalAudioController audio;
  final Map<String, Uint8List> draftImages;
  final TextScaler? textScaler;
  final double lineHeight;
  final double imageMaxHeight;
  final bool zoomImages;
  static final _sound = RegExp(r'\[sound:([^\]\r\n]+)\]');
  static const _blocked = {
    'script',
    'style',
    'iframe',
    'object',
    'embed',
    'form',
    'input',
    'svg',
    'math',
    'video',
    'audio',
    'link',
    'meta',
  };
  static const _blocks = {
    'p',
    'div',
    'blockquote',
    'pre',
    'ul',
    'ol',
    'li',
    'table',
    'thead',
    'tbody',
    'tr',
    'h1',
    'h2',
    'h3',
    'h4',
  };
  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(context)
        .copyWith(textScaler: textScaler ?? FontScaleScope.readingOf(context)),
    child: LayoutBuilder(
      builder: (context, box) {
        final base = Theme.of(context).textTheme.titleLarge!
            .copyWith(height: lineHeight);
        List<InlineSpan> render(
          dom.Node node,
          TextStyle style, [
          int depth = 0,
        ]) {
          if (depth > 64) return const [];
          if (node is dom.Text) {
            final result = <InlineSpan>[];
            var offset = 0;
            for (final match in _sound.allMatches(node.data)) {
              result.add(
                TextSpan(
                  text: node.data.substring(offset, match.start),
                  style: style,
                ),
              );
              result.add(
                WidgetSpan(
                  child: SizedBox(
                    width: box.maxWidth,
                    child: _AudioControl(token: match[1]!, audio: audio),
                  ),
                ),
              );
              offset = match.end;
            }
            result.add(
              TextSpan(text: node.data.substring(offset), style: style),
            );
            return result;
          }
          if (node is! dom.Element || _blocked.contains(node.localName)) {
            return const [];
          }
          final tag = node.localName;
          if (tag == 'br' || tag == 'hr') return [const TextSpan(text: '\n')];
          if (tag == 'img') {
            return [
              WidgetSpan(
                child: SizedBox(
                  width: box.maxWidth,
                  child: _LocalImage(
                    token: node.attributes['src'] ?? '',
                    media: media,
                    draft: draftImages[node.attributes['src']],
                    maxHeight: imageMaxHeight,
                    zoom: zoomImages,
                  ),
                ),
              ),
            ];
          }
          final next = style.copyWith(
            fontWeight: {'b', 'strong', 'th'}.contains(tag)
                ? FontWeight.w700
                : null,
            fontStyle: {'i', 'em'}.contains(tag) ? FontStyle.italic : null,
            decoration: tag == 'u'
                ? TextDecoration.underline
                : tag == 's'
                ? TextDecoration.lineThrough
                : null,
            fontFamily: {'code', 'pre'}.contains(tag) ? 'monospace' : null,
            fontSize: {'sub', 'sup', 'small'}.contains(tag)
                ? (style.fontSize ?? 22) * .75
                : null,
          );
          final children = node.nodes
              .expand((child) => render(child, next, depth + 1))
              .toList();
          if (tag == 'sub' || tag == 'sup') {
            return [
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: Transform.translate(
                  offset: Offset(0, tag == 'sub' ? 4 : -6),
                  child: Text.rich(TextSpan(children: children), style: next),
                ),
              ),
            ];
          }
          return [
            if (_blocks.contains(tag)) const TextSpan(text: '\n'),
            if (tag == 'li') const TextSpan(text: '• '),
            ...children,
            if (tag == 'td' || tag == 'th') const TextSpan(text: '   '),
            if (_blocks.contains(tag)) const TextSpan(text: '\n'),
          ];
        }

        final nodes = html.parseFragment(source).nodes;
        return Text.rich(
          TextSpan(children: nodes.expand((n) => render(n, base)).toList()),
          style: base,
          textWidthBasis: TextWidthBasis.parent,
        );
      },
    ),
  );
}

class _LocalImage extends StatefulWidget {
  const _LocalImage({
    required this.token,
    required this.media,
    this.draft,
    this.maxHeight = 280,
    this.zoom = false,
  });
  final String token;
  final MediaRepository media;
  final Uint8List? draft;
  final double maxHeight;
  final bool zoom;
  @override
  State<_LocalImage> createState() => _LocalImageState();
}

class _LocalImageState extends State<_LocalImage> {
  late Future<LocalMedia?> _asset;
  void _load() => _asset = widget.draft != null
      ? Future.value(null)
      : widget.media.resolve(widget.token, kind: MediaKind.image);
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_LocalImage old) {
    super.didUpdateWidget(old);
    if (old.token != widget.token ||
        old.media != widget.media ||
        old.draft != widget.draft) {
      _load();
    }
  }

  Widget _missing() => const Padding(
    padding: EdgeInsets.all(16),
    child: Text('图片缺失或无法显示', style: TextStyle(fontSize: 16)),
  );
  @override
  Widget build(BuildContext context) {
    if (widget.draft != null) {
      return _image(MemoryImage(widget.draft!));
    }
    return FutureBuilder<LocalMedia?>(
      future: _asset,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          if (widget.zoom) {
            return SizedBox(
              height: widget.maxHeight,
              child: const Center(child: CircularProgressIndicator()),
            );
          }
          return const Padding(
            padding: EdgeInsets.all(16),
            child: LinearProgressIndicator(),
          );
        }
        final asset = snapshot.data;
        if (asset == null) return _missing();
        return _image(FileImage(asset.file));
      },
    );
  }

  Widget _image(ImageProvider provider) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image(
        image: ResizeImage(provider, width: 1220, allowUpscaling: false),
        fit: BoxFit.contain,
        height: widget.maxHeight,
        errorBuilder: (_, _, _) => _missing(),
      ),
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: widget.zoom ? 4 : 12),
      child: !widget.zoom
          ? image
          : Tooltip(
              message: '放大图片',
              child: Semantics(
                button: true,
                label: '放大图片',
                child: GestureDetector(
                  onTap: () => showDialog<void>(
                    context: context,
                    builder: (dialogContext) => Dialog.fullscreen(
                      child: Scaffold(
                        appBar: AppBar(
                          title: const Text('查看图片'),
                          leading: IconButton(
                            tooltip: '关闭图片',
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(dialogContext),
                          ),
                        ),
                        body: SafeArea(
                          child: Center(
                            child: InteractiveViewer(
                              minScale: .5,
                              maxScale: 5,
                              child: Image(
                                image: provider,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  child: image,
                ),
              ),
            ),
    );
  }
}

class _AudioControl extends StatelessWidget {
  const _AudioControl({required this.token, required this.audio});
  final String token;
  final LocalAudioController audio;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: audio,
    builder: (context, _) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PressableAction(
            label: audio.activeToken == token
                ? (audio.loading ? '取消音频载入' : '停止音频')
                : '播放音频',
            onPressed: () => audio.toggle(token),
          ),
          if (audio.errorToken == token)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                audio.error!,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
