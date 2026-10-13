import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../feedback/feedback_controller.dart';

class PressableAction extends StatefulWidget {
  const PressableAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.feedbackController,
  });

  final String label;
  final FutureOr<void> Function()? onPressed;
  final FeedbackController? feedbackController;

  @override
  State<PressableAction> createState() => _PressableActionState();
}

class _PressableActionState extends State<PressableAction> {
  bool _pressed = false;
  bool _busy = false;
  bool _showFocus = false;
  int? _pointer;

  bool get _enabled => widget.onPressed != null && !_busy;

  void _press(PointerDownEvent event) {
    if (!_enabled || _pointer != null || event.buttons != kPrimaryButton) {
      return;
    }
    setState(() {
      _pointer = event.pointer;
      _pressed = true;
    });
  }

  void _release(PointerEvent event) {
    if (event.pointer != _pointer) return;
    setState(() {
      _pointer = null;
      _pressed = false;
    });
  }

  Future<void> _activate() async {
    if (!_enabled) return;
    final action = widget.onPressed!;
    setState(() {
      _busy = true;
      _pressed = false;
      _pointer = null;
    });
    unawaited((widget.feedbackController ?? FeedbackScope.of(context)).tap());
    try {
      await action();
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'CuSO4 pressable action',
          context: ErrorDescription('while executing ${widget.label}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 120);
    final background = _busy
        ? scheme.primaryContainer
        : !_enabled
        ? scheme.onSurface.withValues(alpha: 0.12)
        : _pressed
        ? Color.alphaBlend(
            scheme.onPrimary.withValues(alpha: 0.16),
            scheme.primary,
          )
        : scheme.primary;
    final foreground = _busy
        ? scheme.onPrimaryContainer
        : !_enabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : scheme.onPrimary;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.label,
      value: _busy ? '处理中' : null,
      liveRegion: _busy,
      onTap: _enabled ? _activate : null,
      child: FocusableActionDetector(
        enabled: _enabled,
        onShowFocusHighlight: (value) => setState(() => _showFocus = value),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              unawaited(_activate());
              return null;
            },
          ),
        },
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _press,
          onPointerUp: _release,
          onPointerCancel: _release,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: _enabled ? _activate : null,
            child: AnimatedScale(
              scale: _pressed && !reduceMotion ? 0.96 : 1,
              duration: duration,
              curve: Curves.easeOut,
              child: AnimatedContainer(
                duration: duration,
                curve: Curves.easeOut,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _showFocus ? scheme.onSurface : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: ExcludeSemantics(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_busy) ...[
                        SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: foreground,
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Flexible(
                        child: Text(
                          widget.label,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(color: foreground),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
