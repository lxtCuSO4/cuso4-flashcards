import 'dart:async';
import 'dart:ui' show Tristate;

import 'package:cuso4_flashcards/core/feedback/feedback_controller.dart';
import 'package:cuso4_flashcards/core/widgets/pressable_action.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Widget host(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: Scaffold(body: Center(child: child)),
  ),
);

class RecordingFeedbackPlatform implements FeedbackPlatform {
  final calls = <FeedbackKind>[];
  @override
  Future<void> perform(FeedbackKind kind) async => calls.add(kind);
}

class UnsupportedFeedbackPlatform implements FeedbackPlatform {
  @override
  Future<void> perform(FeedbackKind kind) async =>
      throw MissingPluginException();
}

void main() {
  testWidgets('press changes scale immediately and release restores it', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(PressableAction(label: '学习', onPressed: () {})),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('学习')),
    );
    await tester.pump();
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      0.96,
    );
    await gesture.up();
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });
  testWidgets('busy action shows progress and prevents duplicate submission', (
    tester,
  ) async {
    final completion = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      host(
        PressableAction(
          label: '导入',
          onPressed: () {
            calls++;
            return completion.future;
          },
        ),
      ),
    );
    await tester.tap(find.text('导入'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.byType(PressableAction));
    await tester.pump();
    expect(calls, 1);
    completion.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
  testWidgets(
    'reduced motion keeps pressed color with zero animation duration',
    (tester) async {
      await tester.pumpWidget(
        host(
          PressableAction(label: '学习', onPressed: () {}),
          reduceMotion: true,
        ),
      );
      final idleColor =
          (tester
                      .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                      .decoration
                  as BoxDecoration)
              .color;
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('学习')),
      );
      await tester.pump();
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).duration,
        Duration.zero,
      );
      final pressed = tester.widget<AnimatedContainer>(
        find.byType(AnimatedContainer),
      );
      expect(pressed.duration, Duration.zero);
      expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
      expect((pressed.decoration as BoxDecoration).color, isNot(idleColor));
      await gesture.cancel();
    },
  );
  testWidgets('disabled action stays idle', (tester) async {
    await tester.pumpWidget(
      host(const PressableAction(label: '暂无卡片', onPressed: null)),
    );
    await tester.tap(find.text('暂无卡片'));
    await tester.pump();
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
  });
  testWidgets('accepted taps provide feedback and canceled presses do not', (
    tester,
  ) async {
    final platform = RecordingFeedbackPlatform();
    var calls = 0;
    await tester.pumpWidget(
      host(
        PressableAction(
          label: '学习',
          feedbackController: FeedbackController(platform: platform),
          onPressed: () {
            calls++;
          },
        ),
      ),
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('学习')),
    );
    await tester.pump();
    expect(platform.calls, isEmpty);
    await gesture.cancel();
    await tester.pump();
    expect(calls, 0);
    await tester.tap(find.text('学习'));
    await tester.pump();
    expect(platform.calls, [FeedbackKind.selection]);
    expect(calls, 1);
  });
  testWidgets('unsupported feedback does not prevent the business action', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        PressableAction(
          label: '学习',
          feedbackController: FeedbackController(
            platform: UnsupportedFeedbackPlatform(),
          ),
          onPressed: () {
            calls++;
          },
        ),
      ),
    );
    await tester.tap(find.text('学习'));
    await tester.pump();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
  for (final asynchronous in [false, true]) {
    testWidgets(
      '${asynchronous ? 'async' : 'sync'} operation failure is surfaced and unlocks action',
      (tester) async {
        final failure = StateError('Operation failed');
        var calls = 0;
        await tester.pumpWidget(
          host(
            PressableAction(
              label: '导入',
              onPressed: () {
                calls++;
                if (calls > 1) return Future<void>.value();
                if (asynchronous) return Future<void>.error(failure);
                throw failure;
              },
            ),
          ),
        );
        await tester.tap(find.text('导入'));
        await tester.pump();
        expect(tester.takeException(), same(failure));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(find.text('导入'));
        await tester.pump();
        expect(calls, 2);
      },
    );
  }
  testWidgets(
    'button semantics announce busy and disabled states with a 48dp target',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final completion = Completer<void>();
      await tester.pumpWidget(
        host(PressableAction(label: '导入', onPressed: () => completion.future)),
      );
      final finder = find.byType(PressableAction);
      final size = tester.getSize(finder);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      var node = tester.getSemantics(finder);
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isTrue);
      await tester.tap(find.text('导入'));
      await tester.pump();
      node = tester.getSemantics(finder);
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      expect(node.value, '处理中');
      completion.complete();
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        host(const PressableAction(label: '导入', onPressed: null)),
      );
      node = tester.getSemantics(finder);
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      semantics.dispose();
    },
  );
  testWidgets('keyboard focus is visible and Enter and Space activate once', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        PressableAction(
          label: '学习',
          onPressed: () {
            calls++;
          },
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    final decoration =
        tester
                .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                .decoration
            as BoxDecoration;
    expect((decoration.border as Border).top.color.a, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    expect(calls, 2);
  });
  testWidgets('busy and disabled colors are visibly different from enabled', (
    tester,
  ) async {
    final completion = Completer<void>();
    await tester.pumpWidget(
      host(PressableAction(label: '导入', onPressed: () => completion.future)),
    );
    Color? color() =>
        (tester
                    .widget<AnimatedContainer>(find.byType(AnimatedContainer))
                    .decoration
                as BoxDecoration)
            .color;
    final enabledColor = color();
    await tester.tap(find.text('导入'));
    await tester.pump();
    final busyColor = color();
    expect(busyColor, isNot(enabledColor));
    completion.complete();
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      host(const PressableAction(label: '导入', onPressed: null)),
    );
    expect(color(), isNot(enabledColor));
    expect(color(), isNot(busyColor));
  });
  testWidgets('long labels fit narrow layouts with large text', (tester) async {
    await tester.pumpWidget(
      host(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SizedBox(
            width: 160,
            child: PressableAction(label: '开始学习今天计划的全部卡片', onPressed: () {}),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text('开始学习今天计划的全部卡片'), findsOneWidget);
  });
}
