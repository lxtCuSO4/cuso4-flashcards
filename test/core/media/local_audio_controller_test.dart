import 'dart:async';
import 'dart:io';

import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/media/local_audio_controller.dart';
import 'package:cuso4_flashcards/core/media/media_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class DelayedMedia extends MediaRepository {
  DelayedMedia(super.db);
  final pending = <String, Completer<LocalMedia?>>{};
  @override
  Future<LocalMedia?> resolve(String token, {required MediaKind kind}) =>
      (pending[token] = Completer<LocalMedia?>()).future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test/local_audio');
  late AppDatabase db;
  late DelayedMedia media;
  late LocalAudioController audio;
  final calls = <MethodCall>[];
  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    media = DelayedMedia(db);
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return null;
        });
    audio = LocalAudioController(media, channel: channel);
  });
  tearDown(() async {
    audio.dispose();
    await Future<void>.delayed(Duration.zero);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await db.close();
  });
  final asset = LocalMedia(file: File('local.mp3'), mimeType: 'audio/mpeg');
  test('stopping during resolution prevents late playback', () async {
    final playing = audio.toggle('first');
    await Future<void>.delayed(Duration.zero);
    await audio.stop();
    media.pending['first']!.complete(asset);
    await playing;
    expect(calls.where((c) => c.method == 'play'), isEmpty);
    expect(audio.activeToken, isNull);
  });
  test('switching audio ignores stale resolutions and missing media is recoverable', () async {
    final first = audio.toggle('first');
    await Future<void>.delayed(Duration.zero);
    final second = audio.toggle('second');
    await Future<void>.delayed(Duration.zero);
    media.pending['second']!.complete(asset);
    await second;
    media.pending['first']!.complete(asset);
    await first;
    expect(calls.where((c) => c.method == 'play').length, 1);
    expect(audio.activeToken, 'second');
    await audio.toggle('second');
    expect(audio.activeToken, isNull);
    final missing = audio.toggle('missing');
    await Future<void>.delayed(Duration.zero);
    media.pending['missing']!.complete(null);
    await missing;
    expect(audio.errorToken, 'missing');
    expect(audio.activeToken, isNull);
  });
}
