import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/typography/font_scale_scope.dart';

class ChoiceFitLayout {
  const ChoiceFitLayout({
    required this.textScaler,
    required this.tight,
    required this.imageHeight,
  });
  final TextScaler textScaler;
  final bool tight;
  final double imageHeight;
  double get gap => tight ? 5 : 8;
  double get optionPadding => tight ? 8 : 10;
}

/// Measure real rich-text layout; never scale touch targets or clip long text.
class AdaptiveChoiceViewport extends StatefulWidget {
  const AdaptiveChoiceViewport({
    super.key,
    required this.contentIdentity,
    required this.builder,
  });
  final Object contentIdentity;
  final Widget Function(ChoiceFitLayout) builder;
  @override
  State<AdaptiveChoiceViewport> createState() => _AdaptiveChoiceViewportState();
}

class _AdaptiveChoiceViewportState extends State<AdaptiveChoiceViewport> {
  final _measureKey = GlobalKey();
  final _scroll = ScrollController();
  Object? _signature;
  double _available = 0;
  int _percent = 100;
  int _minimum = 75;
  bool _tight = false;
  bool _ready = false;
  bool _overflow = false;
  bool _scheduled = false;
  bool _resetScroll = true;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scheduleMeasure() {
    if (_scheduled) return;
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted) return;
      final box = _measureKey.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize || _available <= 0) return;
      if (_resetScroll && _scroll.hasClients) {
        _resetScroll = false;
        _scroll.jumpTo(0);
      }
      final height = box.size.height;
      if (height <= _available + .5) {
        if (!_ready || _overflow) {
          setState(() {
            _ready = true;
            _overflow = false;
          });
        }
      } else if (!_tight) {
        setState(() {
          _tight = true;
          _ready = false;
        });
      } else if (_percent > _minimum) {
        final next = (_percent * _available / height * .98).floor().clamp(
          _minimum,
          _percent - 1,
        );
        setState(() {
          _percent = next;
          _ready = false;
        });
      } else if (!_ready || !_overflow) {
        setState(() {
          _ready = true;
          _overflow = true;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final reading = FontScaleScope.readingOf(context);
    final ui = MediaQuery.textScalerOf(context);
    final baseSize = Theme.of(context).textTheme.titleLarge?.fontSize ?? 22;
    return LayoutBuilder(
      builder: (context, constraints) {
        assert(constraints.hasBoundedHeight);
        final signature = (
          widget.contentIdentity,
          constraints.maxWidth,
          constraints.maxHeight,
          reading,
          ui,
        );
        if (_signature != signature) {
          _signature = signature;
          _percent = 100;
          _tight = false;
          _ready = false;
          _overflow = false;
          _resetScroll = true;
        }
        _available = constraints.maxHeight;
        _minimum = math.max(
          75,
          (1600 / reading.scale(baseSize)).ceil().clamp(0, 100),
        );
        final imageHeight = (_available * (_tight ? .18 : .25)).clamp(
          _tight ? 72.0 : 80.0,
          _tight ? 140.0 : 180.0,
        );
        final layout = ChoiceFitLayout(
          textScaler: applyFontPercent(reading, _percent),
          tight: _tight,
          imageHeight: imageHeight,
        );
        _scheduleMeasure();
        return Semantics(
          hint: _overflow ? '内容较长，可以上下滑动查看全部题目' : null,
          child: NotificationListener<SizeChangedLayoutNotification>(
            onNotification: (_) {
              _scheduleMeasure();
              return false;
            },
            child: Scrollbar(
              controller: _scroll,
              thumbVisibility: _ready && _overflow,
              child: SingleChildScrollView(
                key: const ValueKey('adaptive-choice-scroll'),
                controller: _scroll,
                physics: _ready && _overflow
                    ? const ClampingScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                child: SizeChangedLayoutNotifier(
                  child: SizedBox(
                    key: _measureKey,
                    width: double.infinity,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                      child: IgnorePointer(
                        ignoring: !_ready,
                        child: ExcludeSemantics(
                          excluding: !_ready,
                          child: Opacity(
                            opacity: _ready ? 1 : 0,
                            child: widget.builder(layout),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
