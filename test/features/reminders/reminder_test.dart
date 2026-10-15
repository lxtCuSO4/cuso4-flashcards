import 'package:cuso4_flashcards/app/theme/app_theme.dart';
import 'package:cuso4_flashcards/features/reminders/reminder_page.dart';
import 'package:cuso4_flashcards/features/reminders/reminder_platform.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.cuso4.flashcards/reminders');
  final calls = <MethodCall>[];
  var permission = false, fail = false;
  Map<String, Object> state = {};
  setUp(() {
    calls.clear();
    permission = false;
    fail = false;
    state = {'enabled': false, 'hour': 20, 'minute': 0, 'allowed': false};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'state':
              return state;
            case 'requestPermission':
              return permission;
            case 'save':
              if (fail) {
                throw PlatformException(
                  code: 'REMINDER_ERROR',
                  message: '保存失败',
                );
              }
              state = Map<String, Object>.from(call.arguments as Map)
                ..['allowed'] = permission;
              return state;
            default:
              return null;
          }
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null),
  );
  test('channel handles permission denial, state roundtrip, time bounds and native failure', () async {
    final platform = ReminderPlatform();
    expect((await platform.read()).enabled, false);
    expect(await platform.requestPermission(), false);
    await expectLater(
      platform.save(enabled: true, hour: 24, minute: 0),
      throwsArgumentError,
    );
    expect(calls.where((c) => c.method == 'save'), isEmpty);
    permission = true;
    final saved = await platform.save(enabled: true, hour: 7, minute: 35);
    expect(
      (saved.enabled, saved.hour, saved.minute, saved.allowed),
      (true, 7, 35, true),
    );
    fail = true;
    await expectLater(
      platform.save(enabled: false, hour: 7, minute: 35),
      throwsStateError,
    );
    expect((await platform.read()).enabled, true);
    await platform.openSettings();
    await platform.test();
    expect(calls.map((c) => c.method), containsAll(['settings', 'test']));
  });
  testWidgets(
    'phone dark/large text: denied or failed enable retains off state, successful retry enables',
    (tester) async {
      tester.view.physicalSize = const Size(1220, 2712);
      tester.view.devicePixelRatio = 3;
      tester.platformDispatcher.textScaleFactorTestValue = 1.8;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(theme: AppTheme.dark, home: const ReminderPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(calls.where((c) => c.method == 'save'), isEmpty);
      expect(tester.widget<Switch>(find.byType(Switch)).value, false);
      permission = true;
      fail = true;
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, false);
      fail = false;
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(tester.widget<Switch>(find.byType(Switch)).value, true);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );
}
