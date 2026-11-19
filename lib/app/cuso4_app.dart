import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';
import 'router/app_router.dart';
import '../core/feedback/feedback_controller.dart';
import '../core/typography/font_scale_scope.dart';
import '../features/settings/domain/font_settings.dart';
import 'theme/app_theme.dart';

class Cuso4App extends ConsumerWidget {
  const Cuso4App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? {};
    final theme = settings['theme'];
    final strength = settings['feedback'];
    final fonts = FontSettings.decode(settings[FontSettings.settingKey]);
    return MaterialApp.router(
      title: 'Lunar Memory',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: theme == 'dark'
          ? ThemeMode.dark
          : theme == 'light'
          ? ThemeMode.light
          : ThemeMode.system,
      routerConfig: ref.watch(appRouterProvider),
      builder: (context, child) => FontScaleScope(
        system: MediaQuery.textScalerOf(context),
        cardPercent: fonts.cardPercent,
        child: MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: applyFontPercent(
              MediaQuery.textScalerOf(context),
              fonts.uiPercent,
            ),
          ),
          child: FeedbackScope(
            controller: FeedbackController(
              strength: strength == 'gentle'
                  ? FeedbackStrength.gentle
                  : strength == 'off'
                  ? FeedbackStrength.off
                  : FeedbackStrength.strong,
            ),
            child: child!,
          ),
        ),
      ),
    );
  }
}
