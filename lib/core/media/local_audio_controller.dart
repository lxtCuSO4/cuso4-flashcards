import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'media_repository.dart';

/// One player per learning page. No network sources, autoplay or background audio.
class LocalAudioController extends ChangeNotifier {
  LocalAudioController(this.media, {MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.cuso4.flashcards/audio') {
    _channel.setMethodCallHandler(_onEvent);
  }

  final MediaRepository media;
  final MethodChannel _channel;
  String? activeToken;
  String? errorToken;
  String? error;
  bool loading = false;
  bool _disposed = false;
  int _generation = 0;

  Future<void> toggle(String token) async {
    if (_disposed) return;
    if (activeToken == token) {
      await stop();
      return;
    }
    await stop();
    if (_disposed) return;
    final generation = ++_generation;
    activeToken = token;
    loading = true;
    error = errorToken = null;
    _notify();
    try {
      final asset = await media.resolve(token, kind: MediaKind.audio);
      if (_disposed || generation != _generation) return;
      if (asset == null) throw StateError('音频缺失或格式不受支持');
      await _channel.invokeMethod<void>('play', {
        'path': asset.file.path,
        'id': generation,
      });
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    } catch (_) {
      if (!_disposed && generation == _generation) {
        activeToken = null;
        loading = false;
        errorToken = token;
        error = '音频无法播放，请检查本地文件或稍后重试。';
        _notify();
      }
    }
  }

  Future<void> _onEvent(MethodCall call) async {
    final args = call.arguments;
    if (_disposed || args is! Map || args['id'] != _generation) return;
    if (call.method != 'completed' && call.method != 'error') return;
    if (call.method == 'error') {
      errorToken = activeToken;
      error = '音频无法播放，请重试。';
    }
    activeToken = null;
    loading = false;
    _notify();
  }

  Future<void> stop() async {
    ++_generation;
    activeToken = null;
    loading = false;
    error = errorToken = null;
    _notify();
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {
      // Unsupported hosts or released players must not block study actions.
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _channel.setMethodCallHandler(null);
    unawaited(stop());
    super.dispose();
  }
}
