import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/layout/layout_shell.dart';

class SheepApp extends StatelessWidget {
  const SheepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sheep',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      home: const LayoutShell(),
    );
  }
}
