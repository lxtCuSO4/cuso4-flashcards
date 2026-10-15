import 'dart:async';

import 'package:cuso4_flashcards/features/settings/presentation/repository_link_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.cuso4.flashcards/repository_link');
  testWidgets(
    'meme link opens once, then browser failure keeps a copyable address',
    (tester) async {
      final response = Completer<bool>();
      var opens = 0;
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'openRepository');
        opens++;
        return response.future;
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        );
      });
      tester.view.physicalSize = const Size(1220, 2712);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: const RepositoryLinkCard()),
          ),
        ),
      );
      expect(find.byType(Image), findsOneWidget);
      await tester.tap(find.text('GitHub 仓库'));
      await tester.pump();
      await tester.tap(find.text('GitHub 仓库'));
      await tester.pump();
      expect(opens, 1);
      response.complete(false);
      await tester.pumpAndSettle();
      expect(find.textContaining('未能打开浏览器'), findsOneWidget);
      await tester.tap(find.text('复制仓库链接'));
      await tester.pumpAndSettle();
      expect(copied, 'https://github.com/lxtCuSO4/cuso4-flashcards');
      expect(tester.takeException(), isNull);
      // Reuse the same interaction state to check wrapping in dark mode,
      // larger text and a landscape viewport without additional integration runs.
      for (final size in [const Size(375, 812), const Size(904, 407)]) {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(2),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(child: const RepositoryLinkCard()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    },
  );
}
