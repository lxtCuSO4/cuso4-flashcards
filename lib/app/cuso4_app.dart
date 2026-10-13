import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'router/app_router.dart';
import '../core/feedback/feedback_controller.dart';
import 'theme/app_theme.dart';

class Cuso4App extends ConsumerWidget {
  const Cuso4App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = ref.watch(settingsProvider).value?['theme'];
    final strength = ref.watch(settingsProvider).value?['feedback'];
    return MaterialApp.router(
      title: 'CuSO₄闪卡',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: theme == 'dark'
          ? ThemeMode.dark
          : theme == 'light'
          ? ThemeMode.light
          : ThemeMode.system,
      routerConfig: ref.watch(appRouterProvider),
      builder: (_, child) => FeedbackScope(
        controller: FeedbackController(
          strength: strength == 'gentle'
              ? FeedbackStrength.gentle
              : strength == 'off'
              ? FeedbackStrength.off
              : FeedbackStrength.strong,
        ),
        child: child!,
      ),
    );
  }
}
