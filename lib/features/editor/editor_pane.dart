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
import '../search/search_modal.dart';
import '../sections/providers.dart';
import 'providers.dart';

class EditorPane extends ConsumerStatefulWidget {
  const EditorPane({super.key});

  @override
  ConsumerState<EditorPane> createState() => _EditorPaneState();
}

class _EditorPaneState extends ConsumerState<EditorPane> {
  EditorState? _editorState;
  EditorScrollController? _editorScrollController;
  Timer? _debounceTimer;
  String? _currentlyLoadedPageId;

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _editorScrollController?.dispose();
    _editorState?.dispose();
    super.dispose();
  }

  void _initEditorState(db.Page page) {
    _debounceTimer?.cancel();
    _editorScrollController?.dispose();
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
    final newScrollController = EditorScrollController(
      editorState: newEditorState,
      shrinkWrap: true,
    );

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
      _editorScrollController = newScrollController;
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
    final activeSectionId = ref.watch(activeSectionProvider);

    Widget contentChild;

    if (activePageId == null) {
      final hasPages = activeSectionId != null &&
          (ref.watch(pagesProvider(activeSectionId)).value?.isNotEmpty ?? false);

      contentChild = Center(
        key: const ValueKey('empty_state'),
        child: _Placeholder(hasPages: hasPages),
      );
    } else {
      final fullPageAsync = ref.watch(fullPageProvider(activePageId));

      contentChild = Container(
        key: ValueKey(activePageId),
        child: fullPageAsync.when(
          data: (page) {
            if (page == null) return const Center(child: Text('Page not found'));

            if (_currentlyLoadedPageId != page.id) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _initEditorState(page);
              });
              return const Center(child: _DelayedLoader());
            }

            if (_editorState == null || _editorScrollController == null) {
              return const Center(child: _DelayedLoader());
            }

            return FloatingToolbar(
              items: [
                ...markdownFormatItems,
                ...headingItems,
                bulletedListItem,
                numberedListItem,
                quoteItem,
                linkItem,
              ],
              style: FloatingToolbarStyle(
                backgroundColor: colors.surfacePanel,
                toolbarActiveColor: colors.accent,
                toolbarIconColor: colors.inkPrimary,
              ),
              textDirection: TextDirection.ltr,
              editorState: _editorState!,
              editorScrollController: _editorScrollController!,
              child: AppFlowyEditor(
                editorState: _editorState!,
                editorScrollController: _editorScrollController!,
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
              ),
            );
          },
          loading: () => const Center(child: _DelayedLoader()),
          error: (err, stack) => Center(child: Text('Error: $err')),
        ),
      );
    }

    return Container(
      color: colors.surfaceBase,
      child: Column(
        children: [
          _TopBar(colors: colors, editorState: activePageId == null ? null : _editorState),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: contentChild,
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerStatefulWidget {
  const _TopBar({required this.colors, required this.editorState});
  final AppColors colors;
  final EditorState? editorState;

  @override
  ConsumerState<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<_TopBar> {
  String _currentBlockType = ParagraphBlockKeys.type;
  String _currentFontFamily = 'Inter';
  double _currentFontSize = 14.0;

  Selection? _lastSelection;

  @override
  void initState() {
    super.initState();
    widget.editorState?.selectionNotifier.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(_TopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editorState != widget.editorState) {
      oldWidget.editorState?.selectionNotifier.removeListener(_onSelectionChanged);
      widget.editorState?.selectionNotifier.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    widget.editorState?.selectionNotifier.removeListener(_onSelectionChanged);
    super.dispose();
  }

  void _onSelectionChanged() {
    final editorState = widget.editorState;
    final selection = editorState?.selection;
    if (selection != null) {
      _lastSelection = selection;
      // Reflect the current node's block type in the dropdown
      final node = editorState?.getNodeAtPath(selection.start.path);
      if (node != null && mounted) {
        String blockType = node.type;
        // Map heading type + level to our dropdown keys
        if (blockType == HeadingBlockKeys.type) {
          final level = node.attributes[HeadingBlockKeys.level] ?? 1;
          blockType = 'heading$level';
        }
        // Only update if it's a known type in our dropdown
        final knownTypes = {
          ParagraphBlockKeys.type, 'heading1', 'heading2', 'heading3',
          BulletedListBlockKeys.type, NumberedListBlockKeys.type,
          TodoListBlockKeys.type, QuoteBlockKeys.type, 'code',
        };
        if (knownTypes.contains(blockType) && blockType != _currentBlockType) {
          setState(() => _currentBlockType = blockType);
        }
      }

      // Reflect font family and font size
      _updateFontFormattingState(editorState!, selection);
    }
  }

  void _updateFontFormattingState(EditorState editorState, Selection selection) {
    if (selection.isCollapsed) {
      // 1. Check toggled style first (for newly typed text)
      final toggledStyle = editorState.toggledStyle;
      String? toggledFont = toggledStyle[AppFlowyRichTextKeys.fontFamily] as String?;
      double? toggledSize = toggledStyle[AppFlowyRichTextKeys.fontSize] as double?;

      // 2. If not in toggled style, check the character before the cursor
      if (toggledFont == null || toggledSize == null) {
        final attributes = editorState.getDeltaAttributesInSelectionStart(selection);
        if (attributes != null) {
          toggledFont ??= attributes[AppFlowyRichTextKeys.fontFamily] as String?;
          toggledSize ??= attributes[AppFlowyRichTextKeys.fontSize] as double?;
        }
      }

      setState(() {
        _currentFontFamily = toggledFont != null ? _reverseResolveGoogleFont(toggledFont) : 'Inter';
        _currentFontSize = toggledSize ?? 16.0;
      });
    } else {
      // Range selection: collect all font families and sizes in the selection
      final nodes = editorState.getNodesInSelection(selection);
      final Set<String> fontFamilies = {};
      final Set<double> fontSizes = {};

      for (final node in nodes) {
        final delta = node.delta;
        if (delta == null) continue;
        
        // Calculate intersection with selection
        int startOffset = 0;
        int endOffset = delta.length;
        
        if (node.path.equals(selection.start.path)) {
          startOffset = selection.start.offset;
        }
        if (node.path.equals(selection.end.path)) {
          endOffset = selection.end.offset;
        }

        final ops = delta.whereType<TextInsert>();
        int currentOffset = 0;
        
        for (final op in ops) {
          final opStart = currentOffset;
          final opEnd = currentOffset + op.length;
          
          // Check overlap
          if (opStart < endOffset && opEnd > startOffset) {
            final attrs = op.attributes;
            final font = attrs?[AppFlowyRichTextKeys.fontFamily] as String?;
            final size = attrs?[AppFlowyRichTextKeys.fontSize] as double?;
            
            fontFamilies.add(font != null ? _reverseResolveGoogleFont(font) : 'Inter');
            fontSizes.add(size ?? 16.0);
          }
          currentOffset += op.length;
        }
      }

      setState(() {
        if (fontFamilies.isEmpty) {
          _currentFontFamily = 'Inter';
        } else if (fontFamilies.length == 1) {
          _currentFontFamily = fontFamilies.first;
        } else {
          _currentFontFamily = 'Variable';
        }

        if (fontSizes.isEmpty) {
          _currentFontSize = 16.0;
        } else if (fontSizes.length == 1) {
          _currentFontSize = fontSizes.first;
        } else {
          _currentFontSize = -1.0; // special value for Variable
        }
      });
    }
  }

  void _restoreSelectionAndRun(void Function(EditorState editorState, Selection selection) action) {
    final editorState = widget.editorState;
    if (editorState == null) return;
    final selection = _lastSelection ?? editorState.selection;
    if (selection == null) return;

    // Restore the selection in the editor before applying the format
    editorState.updateSelectionWithReason(
      selection,
      reason: SelectionUpdateReason.uiEvent,
    );

    // Run action after the selection is restored
    WidgetsBinding.instance.addPostFrameCallback((_) {
      action(editorState, selection);
    });
  }

  void _applyBlockType(String type) {
    _restoreSelectionAndRun((editorState, selection) {
      if (type.startsWith('heading')) {
        final level = int.parse(type.substring(7));
        editorState.formatNode(
          selection,
          (node) => node.copyWith(
            type: HeadingBlockKeys.type,
            attributes: {
              HeadingBlockKeys.level: level,
              blockComponentBackgroundColor:
                  node.attributes[blockComponentBackgroundColor],
              blockComponentTextDirection:
                  node.attributes[blockComponentTextDirection],
              blockComponentDelta: (node.delta ?? Delta()).toJson(),
            },
          ),
        );
      } else {
        editorState.formatNode(
          selection,
          (node) => node.copyWith(
            type: type,
            attributes: {
              blockComponentBackgroundColor:
                  node.attributes[blockComponentBackgroundColor],
              blockComponentTextDirection:
                  node.attributes[blockComponentTextDirection],
              blockComponentDelta: (node.delta ?? Delta()).toJson(),
            },
          ),
        );
      }
    });
  }

  /// Resolves a Google Fonts display name to its registered fontFamily string,
  /// triggering font download/registration as a side effect.
  String _resolveGoogleFont(String displayName) {
    try {
      final style = GoogleFonts.getFont(displayName);
      return style.fontFamily ?? displayName;
    } catch (_) {
      return displayName;
    }
  }

  String _reverseResolveGoogleFont(String internalName) {
    const displayNames = ['Inter', 'Merriweather', 'JetBrains Mono', 'Roboto', 'Open Sans', 'Lato', 'Poppins', 'Montserrat', 'Playfair Display', 'Source Code Pro'];
    for (final name in displayNames) {
      if (_resolveGoogleFont(name) == internalName) {
        return name;
      }
    }
    return 'Inter'; // Fallback so dropdown doesn't crash
  }

  void _applyFontFamily(String fontFamily) {
    final resolvedFamily = _resolveGoogleFont(fontFamily);
    _restoreSelectionAndRun((editorState, selection) {
      if (selection.isCollapsed) {
        editorState.updateToggledStyle(AppFlowyRichTextKeys.fontFamily, resolvedFamily);
      } else {
        editorState.formatDelta(
          selection,
          {AppFlowyRichTextKeys.fontFamily: resolvedFamily},
        );
      }
    });
  }

  void _applyFontSize(double size) {
    _restoreSelectionAndRun((editorState, selection) {
      if (selection.isCollapsed) {
        editorState.updateToggledStyle(AppFlowyRichTextKeys.fontSize, size);
      } else {
        editorState.formatDelta(
          selection,
          {AppFlowyRichTextKeys.fontSize: size},
        );
      }
    });
  }

  void _insertTable() {
    final editorState = widget.editorState;
    if (editorState == null) return;
    final selection = _lastSelection ?? editorState.selection;
    if (selection == null) return;

    final tableNode = TableNode.fromList(
      [
        ['', ''],
        ['', ''],
      ],
    );

    final transaction = editorState.transaction;
    transaction.insertNode(selection.end.path.next, tableNode.node);
    transaction.afterSelection = Selection.collapsed(
      Position(path: selection.end.path.next),
    );
    editorState.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final editorState = widget.editorState;
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
          
          // Undo / Redo
          _iconBtn(Icons.undo_rounded, 'Undo', () {
            editorState?.undoManager.undo();
          }),
          _iconBtn(Icons.redo_rounded, 'Redo', () {
            editorState?.undoManager.redo();
          }),
          const SizedBox(width: AppSpacing.sm),
          Container(width: 1, height: 20, color: colors.border),
          const SizedBox(width: AppSpacing.sm),
          
          // Block type switcher
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _currentBlockType,
              icon: Icon(Icons.arrow_drop_down, color: colors.inkMuted, size: 16),
              style: TextStyle(color: colors.inkPrimary, fontSize: 13, fontFamily: 'Inter'),
              items: [
                DropdownMenuItem(value: ParagraphBlockKeys.type, child: const Text('Normal text')),
                const DropdownMenuItem(value: 'heading1', child: Text('Heading 1')),
                const DropdownMenuItem(value: 'heading2', child: Text('Heading 2')),
                const DropdownMenuItem(value: 'heading3', child: Text('Subheading')),
                DropdownMenuItem(value: BulletedListBlockKeys.type, child: const Text('Bulleted list')),
                DropdownMenuItem(value: NumberedListBlockKeys.type, child: const Text('Numbered list')),
                DropdownMenuItem(value: TodoListBlockKeys.type, child: const Text('Checklist')),
                DropdownMenuItem(value: QuoteBlockKeys.type, child: const Text('Quote')),
                const DropdownMenuItem(value: 'code', child: Text('Code block')),
              ],
              onChanged: (val) {
                if (editorState != null && val != null) {
                  setState(() => _currentBlockType = val);
                  _applyBlockType(val);
                }
              },
            ),
          ),
          
          const SizedBox(width: AppSpacing.sm),
          Container(width: 1, height: 20, color: colors.border),
          const SizedBox(width: AppSpacing.sm),
          
          // Font family selector
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: _currentFontFamily,
              icon: Icon(Icons.arrow_drop_down, color: colors.inkMuted, size: 16),
              style: TextStyle(color: colors.inkPrimary, fontSize: 13, fontFamily: 'Inter'),
              items: const [
                DropdownMenuItem(value: 'Variable', child: Text('Multiple fonts')),
                DropdownMenuItem(value: 'Inter', child: Text('Inter')),
                DropdownMenuItem(value: 'Merriweather', child: Text('Merriweather')),
                DropdownMenuItem(value: 'JetBrains Mono', child: Text('JetBrains Mono')),
                DropdownMenuItem(value: 'Roboto', child: Text('Roboto')),
                DropdownMenuItem(value: 'Open Sans', child: Text('Open Sans')),
                DropdownMenuItem(value: 'Lato', child: Text('Lato')),
                DropdownMenuItem(value: 'Poppins', child: Text('Poppins')),
                DropdownMenuItem(value: 'Montserrat', child: Text('Montserrat')),
                DropdownMenuItem(value: 'Playfair Display', child: Text('Playfair Display')),
                DropdownMenuItem(value: 'Source Code Pro', child: Text('Source Code Pro')),
              ],
              onChanged: (val) {
                if (editorState != null && val != null) {
                  setState(() => _currentFontFamily = val);
                  _applyFontFamily(val);
                }
              },
            ),
          ),
          
          const SizedBox(width: AppSpacing.sm),
          
          // Font size selector
          DropdownButtonHideUnderline(
            child: DropdownButton<double>(
              value: _currentFontSize,
              icon: Icon(Icons.arrow_drop_down, color: colors.inkMuted, size: 16),
              style: TextStyle(color: colors.inkPrimary, fontSize: 13, fontFamily: 'Inter'),
              items: [-1.0, 10.0, 11.0, 12.0, 13.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0, 36.0, 48.0].map((size) {
                if (size == -1.0) {
                  return const DropdownMenuItem(value: -1.0, child: Text('Multiple'));
                }
                return DropdownMenuItem(value: size, child: Text('${size.toInt()}'));
              }).toList(),
              onChanged: (val) {
                if (editorState != null && val != null) {
                  setState(() => _currentFontSize = val);
                  _applyFontSize(val);
                }
              },
            ),
          ),
          
          const SizedBox(width: AppSpacing.sm),
          Container(width: 1, height: 20, color: colors.border),
          const SizedBox(width: AppSpacing.sm),
          
          // Insert table
          _iconBtn(Icons.table_chart_outlined, 'Insert Table', _insertTable),
          
          const Spacer(),
          
          // Global Search
          _iconBtn(Icons.search, 'Search (Ctrl+K)', () {
            showDialog(
              context: context,
              builder: (context) => const SearchModal(),
            );
          }),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(
        icon,
        color: onPressed != null ? widget.colors.inkSecondary : widget.colors.inkMuted,
        size: 18,
      ),
      onPressed: onPressed ?? () {},
      splashRadius: 16,
      tooltip: tooltip,
    );
  }
}

class _Placeholder extends StatefulWidget {
  const _Placeholder({required this.hasPages});
  final bool hasPages;

  @override
  State<_Placeholder> createState() => _PlaceholderState();
}

class _PlaceholderState extends State<_Placeholder> {
  bool _show = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _show = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();

    final colors = AppTheme.colorsOf(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.edit_note_rounded, color: colors.inkMuted, size: 48),
        const SizedBox(height: AppSpacing.md),
        Text(
          widget.hasPages ? 'Select a page or create a new one' : "Click '+' to get started",
          style: TextStyle(color: colors.inkMuted, fontSize: 14),
        ),
      ],
    );
  }
}

class _DelayedLoader extends StatefulWidget {
  const _DelayedLoader();

  @override
  State<_DelayedLoader> createState() => _DelayedLoaderState();
}

class _DelayedLoaderState extends State<_DelayedLoader> {
  bool _show = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _show = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_show) return const SizedBox.shrink();
    return const CircularProgressIndicator();
  }
}
