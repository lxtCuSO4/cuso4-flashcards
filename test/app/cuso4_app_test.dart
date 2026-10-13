import 'package:cuso4_flashcards/app/cuso4_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the CuSO₄ brand with Material 3 and both themes', (
    tester,
  ) async {
    await tester.pumpWidget(const Cuso4App());
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.title, 'CuSO₄闪卡');
    expect(app.theme!.useMaterial3, isTrue);
    expect(app.darkTheme!.brightness, Brightness.dark);
    expect(app.themeMode, ThemeMode.system);
    expect(find.text('CuSO₄闪卡'), findsOneWidget);
    expect(find.byType(SafeArea), findsWidgets);
  });
}
