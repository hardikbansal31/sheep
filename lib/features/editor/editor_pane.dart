import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/database/database.dart' as db;
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../layout/providers.dart';
import '../pages/providers.dart';
import 'providers.dart';

class EditorPane extends ConsumerStatefulWidget {
  const EditorPane({super.key});

  @override
  ConsumerState<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends ConsumerState<EditorPane> {
  EditorState? _editorState;
  Timer? _debounceTimer;
  String? _currentlyLoadedPageId;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _editorState?.dispose();
    super.dispose();
  }

  void _initEditorState(db.Page page) {
    _debounceTimer?.cancel();
    _editorState?.dispose();

    final jsonMap = jsonDecode(page.contentJson) as Map<String, dynamic>;
    
    // Ensure the first block is a title block for existing pages
    try {
      final documentMap = jsonMap['document'] as Map<String, dynamic>?;
      if (documentMap != null) {
        final children = documentMap['children'] as List<dynamic>?;
        if (children != null) {
          if (children.isNotEmpty) {
            final firstChild = children.first as Map<String, dynamic>;
            if (firstChild['type'] != 'title') {
              firstChild['type'] = 'title';
            }
          } else {
            // Document is empty somehow, add a title block
            children.add({
              'type': 'title',
              'data': {'delta': [{'insert': page.title}]}
            });
            children.add({
              'type': 'paragraph',
              'data': {'delta': [{'insert': ''}]}
            });
          }
        }
      }
    } catch (_) {
      // Ignore parsing errors, let AppFlowy handle it
    }

    final doc = Document.fromJson(jsonMap);
    final newEditorState = EditorState(document: doc);

    newEditorState.transactionStream.listen((event) {
      // Auto-save logic
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
        // Only save if the current loaded page is still the active one
        if (_currentlyLoadedPageId == page.id && ref.read(activePageProvider) == page.id) {
           final title = _extractTitle(newEditorState.document);
           if (title.isEmpty) {
             ScaffoldMessenger.of(context).showSnackBar(
               const SnackBar(content: Text('Title cannot be empty. Reverting to last saved state or please provide a title.')),
             );
             // Skip saving
             return;
           }

           final jsonStr = jsonEncode(newEditorState.document.toJson());
           try {
             await ref.read(repositoryProvider).updatePage(page.id, title, jsonStr);
           } catch (e) {
             debugPrint('Error saving page: $e');
           }
        }
      });
    });

    setState(() {
      _editorState = newEditorState;
      _currentlyLoadedPageId = page.id;
    });
  }

  String _extractTitle(Document document) {
    if (document.root.children.isEmpty) return '';
    final firstNode = document.root.children.first;
    final delta = firstNode.delta;
    return delta?.toPlainText().trim() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final activePageId = ref.watch(activePageProvider);

    if (activePageId == null) {
      return Container(
        color: colors.surfaceBase,
        child: Column(
          children: [
            _TopBar(colors: colors, editorState: null),
            const Expanded(child: Center(child: _Placeholder())),
          ],
        ),
      );
    }

    final fullPageAsync = ref.watch(fullPageProvider(activePageId));

    return Container(
      color: colors.surfaceBase,
      child: Column(
        children: [
          _TopBar(colors: colors, editorState: _editorState),
          Expanded(
            child: fullPageAsync.when(
              data: (page) {
                if (page == null) return const Center(child: Text('Page not found'));

                if (_currentlyLoadedPageId != page.id) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _initEditorState(page);
                  });
                  return const Center(child: CircularProgressIndicator());
                }

                if (_editorState == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                return AppFlowyEditor(
                  editorState: _editorState!,
                  blockComponentBuilders: {
                    ...standardBlockComponentBuilderMap,
                    'title': HeadingBlockComponentBuilder(
                      textStyleBuilder: (level) => GoogleFonts.merriweather(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: colors.accent,
                      ),
                    ),
                  },
                  editorStyle: EditorStyle.desktop(
                    cursorColor: colors.accent,
                    selectionColor: colors.accent.withValues(alpha: 0.2),
                    textStyleConfiguration: TextStyleConfiguration(
                      text: GoogleFonts.inter(
                        fontSize: 16,
                        color: colors.inkPrimary,
                      ),
                      code: GoogleFonts.jetBrainsMono(
                        color: colors.inkPrimary,
                        backgroundColor: colors.surfacePanel,
                      ),
                    ),
                  ),
                  characterShortcutEvents: [
                    ...standardCharacterShortcutEvents.where((e) => e != slashCommand),
                    customSlashCommand(
                      standardSelectionMenuItems,
                      style: SelectionMenuStyle(
                        selectionMenuBackgroundColor: colors.surfacePanel,
                        selectionMenuItemTextColor: colors.inkPrimary,
                        selectionMenuItemIconColor: colors.inkPrimary,
                        selectionMenuItemSelectedTextColor: colors.accent,
                        selectionMenuItemSelectedIconColor: colors.accent,
                        selectionMenuItemSelectedColor: Colors.transparent,
                        selectionMenuUnselectedLabelColor: colors.inkMuted,
                        selectionMenuDividerColor: colors.border,
                        selectionMenuLinkBorderColor: colors.border,
                        selectionMenuInvalidLinkColor: Colors.red,
                        selectionMenuButtonColor: colors.accent,
                        selectionMenuButtonTextColor: colors.surfaceBase,
                        selectionMenuButtonIconColor: colors.surfaceBase,
                        selectionMenuButtonBorderColor: colors.accent,
                        selectionMenuTabIndicatorColor: colors.accent,
                      ),
                    ),
                  ],
                  contextMenuBuilder: (context, position, editorState, onPressed) => const SizedBox.shrink(),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar({required this.colors, required this.editorState});
  final AppColors colors;
  final EditorState? editorState;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showSections = ref.watch(sectionsPaneVisibleProvider);
    final showPages = ref.watch(pagesPaneVisibleProvider);

    return Container(
      height: AppSpacing.xxl,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          // Pane toggles (only show if hidden)
          if (!showSections)
            _iconBtn(Icons.view_sidebar_outlined, 'Show sections', () {
              ref.read(sectionsPaneVisibleProvider.notifier).toggle();
            }),
          if (!showPages)
            _iconBtn(Icons.menu_outlined, 'Show pages', () {
              ref.read(pagesPaneVisibleProvider.notifier).toggle();
            }),
          if (!showSections || !showPages) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(width: 1, height: 20, color: colors.border),
            const SizedBox(width: AppSpacing.sm),
          ],
          // Formatting icons
          _iconBtn(Icons.undo_rounded, 'Undo', () {
            editorState?.undoManager.undo();
          }),
          _iconBtn(Icons.redo_rounded, 'Redo', () {
            editorState?.undoManager.redo();
          }),
          const SizedBox(width: AppSpacing.sm),
          Container(width: 1, height: 20, color: colors.border),
          const SizedBox(width: AppSpacing.sm),
          _iconBtn(Icons.format_bold_rounded, 'Bold', () {
            editorState?.toggleAttribute(AppFlowyRichTextKeys.bold);
          }),
          _iconBtn(Icons.format_italic_rounded, 'Italic', () {
            editorState?.toggleAttribute(AppFlowyRichTextKeys.italic);
          }),
          _iconBtn(Icons.format_underlined_rounded, 'Underline', () {
            editorState?.toggleAttribute(AppFlowyRichTextKeys.underline);
          }),
          const Spacer(),
          _iconBtn(Icons.more_horiz_rounded, 'More', null),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(
        icon,
        color: onPressed != null ? colors.inkSecondary : colors.inkMuted,
        size: 18,
      ),
      onPressed: onPressed ?? () {},
      splashRadius: 16,
      tooltip: tooltip,
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder();

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.edit_note_rounded, color: colors.inkMuted, size: 48),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Select a page to start editing',
          style: TextStyle(color: colors.inkMuted, fontSize: 14),
        ),
      ],
    );
  }
}
