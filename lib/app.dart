import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'features/layout/layout_shell.dart';
import 'features/search/search_modal.dart';
import 'features/settings/providers.dart';

class SearchIntent extends Intent {
  const SearchIntent();
}

class SheepApp extends ConsumerWidget {
  const SheepApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    final themeMode = settingsAsync.value?.themeMode ?? ThemeMode.system;

    return MaterialApp(
      title: 'Sheep',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
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
