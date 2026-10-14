import 'package:cuso4_flashcards/core/content/card_content.dart';
import 'package:cuso4_flashcards/core/database/app_database.dart';
import 'package:cuso4_flashcards/core/media/local_audio_controller.dart';
import 'package:cuso4_flashcards/core/media/media_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'ignores executable HTML and remote sources, shows missing media and audio controls',
    (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      final media = MediaRepository(db);
      final audio = LocalAudioController(media);
      const channel = MethodChannel('com.cuso4.flashcards/audio');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CardContent(
              source:
                  '<b>安全文字</b><script>hiddenScript</script><iframe>hiddenFrame</iframe>'
                  '<img src="https://example.com/image.png">[sound:missing.mp3]',
              media: media,
              audio: audio,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('hiddenScript', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('hiddenFrame', findRichText: true),
        findsNothing,
      );
      expect(find.text('图片缺失或无法显示'), findsOneWidget);
      await tester.tap(find.text('播放音频'));
      await tester.pumpAndSettle();
      expect(find.text('音频无法播放，请检查本地文件或稍后重试。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      audio.dispose();
      await db.close();
    },
  );
}
