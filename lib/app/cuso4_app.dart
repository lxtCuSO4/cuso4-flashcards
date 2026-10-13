import 'package:flutter/material.dart';

import 'theme/app_theme.dart';

class Cuso4App extends StatelessWidget {
  const Cuso4App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CuSO₄闪卡',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      home: const Scaffold(
        body: SafeArea(child: Center(child: Text('CuSO₄闪卡'))),
      ),
    );
  }
}
