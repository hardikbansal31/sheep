import 'package:flutter/material.dart';

import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'features/layout/layout_shell.dart';
import 'features/search/search_modal.dart';

class SearchIntent extends Intent {
  const SearchIntent();
}

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
      home: Builder(
        builder: (context) {
          return Shortcuts(
            shortcuts: <ShortcutActivator, Intent>{
              const SingleActivator(LogicalKeyboardKey.keyK, meta: true): const SearchIntent(),
              const SingleActivator(LogicalKeyboardKey.keyK, control: true): const SearchIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                SearchIntent: CallbackAction<SearchIntent>(
                  onInvoke: (SearchIntent intent) {
                    showDialog(
                      context: context,
                      builder: (context) => const SearchModal(),
                    );
                    return null;
                  },
                ),
              },
              child: const FocusScope(
                autofocus: true,
                child: LayoutShell(),
              ),
            ),
          );
        }
      ),
    );
  }
}
