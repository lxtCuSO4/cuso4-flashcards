import 'package:cuso4_flashcards/features/settings/presentation/problem_feedback_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.cuso4.flashcards/problem_feedback');
  final calls = <MethodCall>[];
  var available = true;
  String? copied;
  setUp(() {
    available = true;
    calls.clear();
    copied = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return available;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  Future<void> tap(WidgetTester tester, String label) async {
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1220, 2712);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: const ProblemFeedbackPage(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester) async {
    final title = find.byKey(const ValueKey('feedback-title'));
    await tester.ensureVisible(title);
    await tester.enterText(title, '图片 & 选择题');
    final details = find.byKey(const ValueKey('feedback-details'));
    await tester.ensureVisible(details);
    await tester.enterText(details, '第一行\n第二行 + 问题？');
  }

  testWidgets(
    'validates required fields and hands draft to email without clearing it',
    (tester) async {
      await open(tester);
      await tap(tester, '打开邮件应用');
      expect(calls, isEmpty);
      expect(find.text('请填写标题'), findsOneWidget);
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: find.byKey(const ValueKey('feedback-title')),
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      await fill(tester);
      await tap(tester, '打开邮件应用');
      expect(calls.single.method, 'openEmail');
      final args = calls.single.arguments as Map;
      expect(args['subject'], contains('图片 & 选择题'));
      expect(args['body'], contains('第一行\n第二行 + 问题？'));
      expect(find.text('请在邮件应用中确认发送，当前表单已保留。'), findsOneWidget);
      expect(
        tester
            .widget<TextFormField>(find.byKey(const ValueKey('feedback-title')))
            .controller!
            .text,
        '图片 & 选择题',
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'no email app offers copy and keeps content at landscape large text',
    (tester) async {
      await open(tester);
      await fill(tester);
      available = false;
      await tap(tester, '打开邮件应用');
      expect(find.text('未能打开邮件应用。可以复制反馈，稍后自行发送。'), findsOneWidget);
      await tap(tester, '复制反馈内容');
      expect(copied, contains('lixingtong035@163.com'));
      expect(copied, contains('第一行\n第二行 + 问题？'));
      tester.view.physicalSize = const Size(2712, 1220);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving a filled form is guarded and cancellation retains it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const ProblemFeedbackPage(),
                ),
              ),
              child: const Text('入口'),
            ),
          ),
        ),
      ),
    );
    await tap(tester, '入口');
    await fill(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('离开反馈页面？'), findsOneWidget);
    await tap(tester, '取消');
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('feedback-title')))
          .controller!
          .text,
      '图片 & 选择题',
    );
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tap(tester, '离开');
    expect(find.text('入口'), findsOneWidget);
  });
}
