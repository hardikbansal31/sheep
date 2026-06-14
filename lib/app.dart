import 'dart:io' show exit;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:flutter/services.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

import 'core/theme/app_theme.dart';
import 'features/layout/layout_shell.dart';
import 'features/search/search_modal.dart';
import 'features/settings/providers.dart';
import 'features/settings/settings_modal.dart';
import 'features/editor/editor_pane.dart';
import 'features/editor/providers.dart';
import 'features/layout/providers.dart';
import 'features/pages/providers.dart';
import 'features/export/export_service.dart';
import 'features/export/pdf_exporter.dart';

class SearchIntent extends Intent { const SearchIntent(); }
class BulletsIntent extends Intent { const BulletsIntent(); }
class CheckIntent extends Intent { const CheckIntent(); }
class NumberedIntent extends Intent { const NumberedIntent(); }
class QuitIntent extends Intent { const QuitIntent(); }
class SettingsIntent extends Intent { const SettingsIntent(); }
class SectionPanelIntent extends Intent { const SectionPanelIntent(); }
class PagePanelIntent extends Intent { const PagePanelIntent(); }
class ExportPdfIntent extends Intent { const ExportPdfIntent(); }

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
              const SingleActivator(LogicalKeyboardKey.period, control: true): const BulletsIntent(),
              const SingleActivator(LogicalKeyboardKey.period, meta: true): const BulletsIntent(),
              const SingleActivator(LogicalKeyboardKey.slash, control: true): const CheckIntent(),
              const SingleActivator(LogicalKeyboardKey.slash, meta: true): const CheckIntent(),
              const SingleActivator(LogicalKeyboardKey.digit1, control: true): const NumberedIntent(),
              const SingleActivator(LogicalKeyboardKey.digit1, meta: true): const NumberedIntent(),
              const SingleActivator(LogicalKeyboardKey.keyQ, control: true): const QuitIntent(),
              const SingleActivator(LogicalKeyboardKey.keyQ, meta: true): const QuitIntent(),
              const SingleActivator(LogicalKeyboardKey.comma, control: true): const SettingsIntent(),
              const SingleActivator(LogicalKeyboardKey.comma, meta: true): const SettingsIntent(),
              const SingleActivator(LogicalKeyboardKey.keyS, control: true): const SectionPanelIntent(),
              const SingleActivator(LogicalKeyboardKey.keyS, meta: true): const SectionPanelIntent(),
              const SingleActivator(LogicalKeyboardKey.keyT, control: true): const PagePanelIntent(),
              const SingleActivator(LogicalKeyboardKey.keyT, meta: true): const PagePanelIntent(),
              const SingleActivator(LogicalKeyboardKey.keyP, control: true): const ExportPdfIntent(),
              const SingleActivator(LogicalKeyboardKey.keyP, meta: true): const ExportPdfIntent(),
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
                BulletsIntent: CallbackAction<BulletsIntent>(
                  onInvoke: (intent) {
                    editorPaneKey.currentState?.applyBlockType(BulletedListBlockKeys.type);
                    return null;
                  },
                ),
                CheckIntent: CallbackAction<CheckIntent>(
                  onInvoke: (intent) {
                    editorPaneKey.currentState?.applyBlockType(TodoListBlockKeys.type);
                    return null;
                  },
                ),
                NumberedIntent: CallbackAction<NumberedIntent>(
                  onInvoke: (intent) {
                    editorPaneKey.currentState?.applyBlockType(NumberedListBlockKeys.type);
                    return null;
                  },
                ),
                QuitIntent: CallbackAction<QuitIntent>(
                  onInvoke: (intent) {
                    if (!kIsWeb) {
                      exit(0);
                    } else {
                      SystemNavigator.pop();
                    }
                    return null;
                  },
                ),
                SettingsIntent: CallbackAction<SettingsIntent>(
                  onInvoke: (intent) {
                    showDialog(
                      context: context,
                      builder: (context) => const SettingsModal(),
                    );
                    return null;
                  },
                ),
                SectionPanelIntent: CallbackAction<SectionPanelIntent>(
                  onInvoke: (intent) {
                    ref.read(sectionsPaneVisibleProvider.notifier).toggle();
                    return null;
                  },
                ),
                PagePanelIntent: CallbackAction<PagePanelIntent>(
                  onInvoke: (intent) {
                    ref.read(pagesPaneVisibleProvider.notifier).toggle();
                    return null;
                  },
                ),
                ExportPdfIntent: CallbackAction<ExportPdfIntent>(
                  onInvoke: (intent) async {
                    final activePageId = ref.read(activePageProvider);
                    if (activePageId != null) {
                      final pageAsync = ref.read(fullPageProvider(activePageId));
                      final page = pageAsync.value;
                      if (page != null) {
                        try {
                          final safeTitle = page.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
                          final pdfBytes = await PdfExporter.export(page.contentJson);
                          await ExportService.exportBytes(pdfBytes, '${safeTitle.isEmpty ? "Untitled" : safeTitle}.pdf');
                        } catch (e) {
                          debugPrint('Error exporting to PDF: $e');
                        }
                      }
                    }
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
