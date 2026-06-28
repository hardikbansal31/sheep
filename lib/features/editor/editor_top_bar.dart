import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/sheep_dropdown.dart';
import '../export/export_service.dart';
import '../export/markdown_exporter.dart';
import '../export/pdf_exporter.dart';
import '../layout/providers.dart';
import '../settings/settings_state.dart';
import '../../core/auth/auth_providers.dart';

class EditorTopBar extends ConsumerStatefulWidget {
  const EditorTopBar({
    super.key,
    required this.colors,
    required this.editorState,
    required this.settings,
    required this.onToggleFindReplace,
  });
  final AppColors colors;
  final EditorState? editorState;
  final SettingsState settings;
  final VoidCallback onToggleFindReplace;

  @override
  ConsumerState<EditorTopBar> createState() => EditorTopBarState();
}

class EditorTopBarState extends ConsumerState<EditorTopBar> {
  static const _fontDisplayNames = [
    'Inter',
    'Merriweather',
    'JetBrains Mono',
    'Roboto',
    'Open Sans',
    'Lato',
    'Poppins',
    'Montserrat',
    'Playfair Display',
    'Source Code Pro',
  ];

  /// internal fontFamily → display name (built once in initState)
  final Map<String, String> _fontReverseLookup = {};
  /// display name → internal fontFamily (built once in initState)
  final Map<String, String> _fontForwardLookup = {};

  String _currentBlockType = ParagraphBlockKeys.type;
  late String _currentFontFamily = widget.settings.fontParagraph;
  late double _currentFontSize = widget.settings.defaultFontSize;
  bool _isCollapsed = false;

  Selection? _lastSelection;

  @override
  void initState() {
    super.initState();
    // Build font lookup maps once — avoids calling GoogleFonts.getFont
    // in a loop on every selection change.
    for (final displayName in _fontDisplayNames) {
      try {
        final internal = GoogleFonts.getFont(displayName).fontFamily ?? displayName;
        _fontForwardLookup[displayName] = internal;
        _fontReverseLookup[internal] = displayName;
      } catch (_) {
        _fontForwardLookup[displayName] = displayName;
        _fontReverseLookup[displayName] = displayName;
      }
    }
    widget.editorState?.selectionNotifier.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(EditorTopBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.editorState != widget.editorState) {
      oldWidget.editorState?.selectionNotifier.removeListener(
        _onSelectionChanged,
      );
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
        const knownTypes = {
          ParagraphBlockKeys.type,
          'heading1',
          'heading2',
          'heading3',
          BulletedListBlockKeys.type,
          NumberedListBlockKeys.type,
          TodoListBlockKeys.type,
          QuoteBlockKeys.type,
          'code',
        };
        if (knownTypes.contains(blockType) && blockType != _currentBlockType) {
          setState(() => _currentBlockType = blockType);
        }
      }

      // Reflect font family and font size
      _updateFontFormattingState(editorState!, selection);
    }
  }

  void _updateFontFormattingState(
    EditorState editorState,
    Selection selection,
  ) {
    String newFontFamily;
    double newFontSize;

    String baseFontFamily = widget.settings.fontParagraph;
    final startNode = editorState.getNodeAtPath(selection.start.path);
    if (startNode != null) {
      if (startNode.type == 'title') {
        baseFontFamily = widget.settings.fontTitle;
      } else if (startNode.type == HeadingBlockKeys.type) {
        baseFontFamily = widget.settings.fontHeadings;
      } else if (startNode.type == 'code') {
        baseFontFamily = widget.settings.fontCode;
      }
    }

    if (selection.isCollapsed) {
      // 1. Check toggled style first (for newly typed text)
      final toggledStyle = editorState.toggledStyle;
      String? toggledFont =
          toggledStyle[AppFlowyRichTextKeys.fontFamily] as String?;
      double? toggledSize =
          toggledStyle[AppFlowyRichTextKeys.fontSize] as double?;

      // 2. If not in toggled style, check the character before the cursor
      if (toggledFont == null || toggledSize == null) {
        final attributes = editorState.getDeltaAttributesInSelectionStart(
          selection,
        );
        if (attributes != null) {
          toggledFont ??=
              attributes[AppFlowyRichTextKeys.fontFamily] as String?;
          toggledSize ??= attributes[AppFlowyRichTextKeys.fontSize] as double?;
        }
      }

      newFontFamily = toggledFont != null
          ? _reverseResolveGoogleFont(toggledFont)
          : baseFontFamily;
      newFontSize = toggledSize ?? widget.settings.defaultFontSize;
    } else {
      // Range selection: collect all font families and sizes in the selection
      final nodes = editorState.getNodesInSelection(selection);
      final Set<String> fontFamilies = {};
      final Set<double> fontSizes = {};

      for (final node in nodes) {
        String nodeBaseFont = widget.settings.fontParagraph;
        if (node.type == 'title') {
          nodeBaseFont = widget.settings.fontTitle;
        } else if (node.type == HeadingBlockKeys.type) {
          nodeBaseFont = widget.settings.fontHeadings;
        } else if (node.type == 'code') {
          nodeBaseFont = widget.settings.fontCode;
        }

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

            fontFamilies.add(
              font != null
                  ? _reverseResolveGoogleFont(font)
                  : nodeBaseFont,
            );
            fontSizes.add(size ?? widget.settings.defaultFontSize);
          }
          currentOffset += op.length;
        }
      }

      if (fontFamilies.isEmpty) {
        newFontFamily = baseFontFamily;
      } else if (fontFamilies.length == 1) {
        newFontFamily = fontFamilies.first;
      } else {
        newFontFamily = 'Variable';
      }

      if (fontSizes.isEmpty) {
        newFontSize = widget.settings.defaultFontSize;
      } else if (fontSizes.length == 1) {
        newFontSize = fontSizes.first;
      } else {
        newFontSize = -1.0; // special value for Variable
      }
    }

    // Only rebuild if something actually changed
    if (newFontFamily != _currentFontFamily ||
        newFontSize != _currentFontSize) {
      setState(() {
        _currentFontFamily = newFontFamily;
        _currentFontSize = newFontSize;
      });
    }
  }

  void _restoreSelectionAndRun(
    void Function(EditorState editorState, Selection selection) action,
  ) {
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

  /// Resolves a Google Fonts display name to its registered fontFamily string.
  /// Uses the cached forward lookup map built in initState.
  String _resolveGoogleFont(String displayName) {
    return _fontForwardLookup[displayName] ?? displayName;
  }

  /// Resolves an internal fontFamily string back to its display name.
  /// Uses the cached reverse lookup map built in initState.
  String _reverseResolveGoogleFont(String internalName) {
    return _fontReverseLookup[internalName] ?? 'Inter';
  }

  void _applyFontFamily(String fontFamily) {
    final resolvedFamily = _resolveGoogleFont(fontFamily);
    _restoreSelectionAndRun((editorState, selection) {
      if (selection.isCollapsed) {
        editorState.updateToggledStyle(
          AppFlowyRichTextKeys.fontFamily,
          resolvedFamily,
        );
      } else {
        editorState.formatDelta(selection, {
          AppFlowyRichTextKeys.fontFamily: resolvedFamily,
        });
      }
    });
  }

  void _applyFontSize(double size) {
    _restoreSelectionAndRun((editorState, selection) {
      if (selection.isCollapsed) {
        editorState.updateToggledStyle(AppFlowyRichTextKeys.fontSize, size);
      } else {
        editorState.formatDelta(selection, {
          AppFlowyRichTextKeys.fontSize: size,
        });
      }
    });
  }

  void _insertTable() {
    final editorState = widget.editorState;
    if (editorState == null) return;
    final selection = _lastSelection ?? editorState.selection;
    if (selection == null) return;

    final tableNode = TableNode.fromList([
      ['', ''],
      ['', ''],
    ]);

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
    final isMobileWidth = MediaQuery.of(context).size.width < 760;

    return Container(
      height: AppSpacing.xxl,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (isMobileWidth)
                    _iconBtn(Icons.arrow_back_rounded, 'Back', () {
                      ref.read(mobileNavIndexProvider.notifier).back();
                    }),
                  if (isMobileWidth) const SizedBox(width: AppSpacing.sm),

                  if (!isMobileWidth && !showSections)
                    _iconBtn(Icons.view_sidebar_outlined, 'Show sections', () {
                      ref.read(sectionsPaneVisibleProvider.notifier).toggle();
                    }),
                  if (!isMobileWidth && !showPages)
                    _iconBtn(Icons.menu_outlined, 'Show pages', () {
                      ref.read(pagesPaneVisibleProvider.notifier).toggle();
                    }),
                  if (!isMobileWidth && (!showSections || !showPages)) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Container(width: 1, height: 20, color: colors.border),
                    const SizedBox(width: AppSpacing.sm),
                  ],

                  if (!isMobileWidth) ...[
                    // Collapse button
                    _iconBtn(
                      _isCollapsed
                          ? Icons.chevron_right_rounded
                          : Icons.chevron_left_rounded,
                      _isCollapsed
                          ? 'Expand formatting options'
                          : 'Collapse formatting options',
                      () {
                        setState(() {
                          _isCollapsed = !_isCollapsed;
                        });
                      },
                    ),

                    if (!_isCollapsed) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Container(width: 1, height: 20, color: colors.border),
                      const SizedBox(width: AppSpacing.sm),

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
                    SheepDropdown<String>(
                      value: _currentBlockType,
                      dropdownWidth: 160,
                      selectedItemBuilder: (context, selectedItem) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                selectedItem.label,
                                style: TextStyle(
                                  color: colors.inkPrimary,
                                  fontSize: 13,
                                  fontFamily: 'Inter',
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down, color: colors.inkMuted, size: 16),
                            ],
                          ),
                        );
                      },
                      items: [
                        SheepDropdownItem(value: ParagraphBlockKeys.type, label: 'Normal text'),
                        const SheepDropdownItem(value: 'heading1', label: 'Heading 1'),
                        const SheepDropdownItem(value: 'heading2', label: 'Heading 2'),
                        const SheepDropdownItem(value: 'heading3', label: 'Subheading'),
                        SheepDropdownItem(value: BulletedListBlockKeys.type, label: 'Bulleted list'),
                        SheepDropdownItem(value: NumberedListBlockKeys.type, label: 'Numbered list'),
                        SheepDropdownItem(value: TodoListBlockKeys.type, label: 'Checklist'),
                        SheepDropdownItem(value: QuoteBlockKeys.type, label: 'Quote'),
                        const SheepDropdownItem(value: 'code', label: 'Code block'),
                      ],
                      onChanged: (val) {
                        if (editorState != null) {
                          setState(() => _currentBlockType = val);
                          _applyBlockType(val);
                        }
                      },
                    ),

                    const SizedBox(width: AppSpacing.sm),
                    Container(width: 1, height: 20, color: colors.border),
                    const SizedBox(width: AppSpacing.sm),

                    // Font family selector
                    SheepDropdown<String>(
                      value: _currentFontFamily,
                      dropdownWidth: 160,
                      selectedItemBuilder: (context, selectedItem) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                selectedItem.label,
                                style: TextStyle(
                                  color: colors.inkPrimary,
                                  fontSize: 13,
                                  fontFamily: 'Inter',
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down, color: colors.inkMuted, size: 16),
                            ],
                          ),
                        );
                      },
                      items: const [
                        SheepDropdownItem(value: 'Variable', label: 'Multiple fonts'),
                        SheepDropdownItem(value: 'Inter', label: 'Inter'),
                        SheepDropdownItem(value: 'Merriweather', label: 'Merriweather'),
                        SheepDropdownItem(value: 'JetBrains Mono', label: 'JetBrains Mono'),
                        SheepDropdownItem(value: 'Roboto', label: 'Roboto'),
                        SheepDropdownItem(value: 'Open Sans', label: 'Open Sans'),
                        SheepDropdownItem(value: 'Lato', label: 'Lato'),
                        SheepDropdownItem(value: 'Poppins', label: 'Poppins'),
                        SheepDropdownItem(value: 'Montserrat', label: 'Montserrat'),
                        SheepDropdownItem(value: 'Playfair Display', label: 'Playfair Display'),
                        SheepDropdownItem(value: 'Source Code Pro', label: 'Source Code Pro'),
                      ],
                      onChanged: (val) {
                        if (editorState != null) {
                          setState(() => _currentFontFamily = val);
                          _applyFontFamily(val);
                        }
                      },
                    ),

                    const SizedBox(width: AppSpacing.sm),

                    // Font size selector
                    SheepDropdown<double>(
                      value: _currentFontSize,
                      dropdownWidth: 100,
                      selectedItemBuilder: (context, selectedItem) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                selectedItem.label,
                                style: TextStyle(
                                  color: colors.inkPrimary,
                                  fontSize: 13,
                                  fontFamily: 'Inter',
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.arrow_drop_down, color: colors.inkMuted, size: 16),
                            ],
                          ),
                        );
                      },
                      items: [
                        -1.0, 10.0, 11.0, 12.0, 13.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0, 36.0, 48.0,
                      ].map((size) {
                        if (size == -1.0) {
                          return const SheepDropdownItem(value: -1.0, label: 'Multiple');
                        }
                        return SheepDropdownItem(value: size, label: '${size.toInt()}');
                      }).toList(),
                      onChanged: (val) {
                        if (editorState != null) {
                          setState(() => _currentFontSize = val);
                          _applyFontSize(val);
                        }
                      },
                    ),

                    const SizedBox(width: AppSpacing.sm),
                    Container(width: 1, height: 20, color: colors.border),
                    const SizedBox(width: AppSpacing.sm),

                    // Insert table
                    _iconBtn(
                      Icons.table_chart_outlined,
                      'Insert Table',
                      _insertTable,
                    ),
                    ],
                  ],
                ],
              ),
            ),
          ),

          // Right side fixed items
          if (ref.watch(unlockedSessionProvider.select((s) => s.isNotEmpty)))
            _iconBtn(Icons.lock_reset, 'Lock active items', () {
              ref.read(unlockedSessionProvider.notifier).clear();
              if (isMobileWidth) {
                // If on mobile, closing the lock might drop the active page if it's protected
                // But EditorPane handles the fallback.
              }
            }),
          if (editorState != null) _exportBtn(),

          // Local Find and Replace
          _iconBtn(Icons.find_replace_outlined, 'Find and Replace (Ctrl+F)', () {
            widget.onToggleFindReplace();
          }),
        ],
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback? onPressed) {
    return IconButton(
      icon: Icon(
        icon,
        color: onPressed != null
            ? widget.colors.inkSecondary
            : widget.colors.inkMuted,
        size: 18,
      ),
      onPressed: onPressed ?? () {},
      splashRadius: 16,
      tooltip: tooltip,
    );
  }

  String _extractTitle(Document document) {
    if (document.root.children.isEmpty) return '';
    final firstNode = document.root.children.first;
    final delta = firstNode.delta;
    return delta?.toPlainText().trim() ?? '';
  }

  Widget _exportBtn() {
    return Tooltip(
      message: 'Export (PDF: Ctrl+P)',
      child: SheepDropdown<String>(
        value: '',
        dropdownWidth: 180,
        alignRight: true,
        selectedItemBuilder: (context, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Icon(Icons.ios_share, color: widget.colors.inkSecondary, size: 18),
        ),
        items: [
          SheepDropdownItem(
            value: 'markdown',
            label: 'Export Markdown',
            icon: Icon(Icons.description, size: 16, color: widget.colors.inkPrimary),
          ),
          SheepDropdownItem(
            value: 'pdf',
            label: 'Export PDF',
            icon: Icon(Icons.picture_as_pdf, size: 16, color: widget.colors.inkPrimary),
          ),
          SheepDropdownItem(
            value: 'copy',
            label: 'Copy to Clipboard',
            icon: Icon(Icons.copy, size: 16, color: widget.colors.inkPrimary),
          ),
        ],
        onChanged: (value) async {
          if (widget.editorState == null) return;
          final contentStr = jsonEncode(widget.editorState!.document.toJson());

          final title = _extractTitle(widget.editorState!.document);
          final safeTitle = title.isEmpty
              ? 'Untitled'
              : title.replaceAll(RegExp(r'[^\w\s]+'), '').replaceAll(' ', '_');

          if (value == 'markdown') {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: widget.colors.surfacePanel,
                title: Text(
                  'Export Markdown',
                  style: TextStyle(color: widget.colors.inkPrimary),
                ),
                content: Text(
                  'Exporting to Markdown is lossy. Font families and precise font sizes will be dropped.',
                  style: TextStyle(color: widget.colors.inkPrimary),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: widget.colors.inkMuted),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(
                      'Continue',
                      style: TextStyle(color: widget.colors.accent),
                    ),
                  ),
                ],
              ),
            );

            if (confirmed == true) {
              final md = MarkdownExporter.export(contentStr);
              await ExportService.exportString(md, '$safeTitle.md');
            }
          } else if (value == 'pdf') {
            final pdfBytes = await PdfExporter.export(contentStr);
            await ExportService.exportBytes(pdfBytes, '$safeTitle.pdf');
          } else if (value == 'copy') {
            final lastSelectable = widget.editorState!.getLastSelectable();
            if (lastSelectable != null) {
              final start = Position(path: [0]);
              final end = lastSelectable.$2.end(lastSelectable.$1);
              final selection = Selection(start: start, end: end);
              final text = widget.editorState!.getTextInSelection(selection).join('\n');
              await Clipboard.setData(ClipboardData(text: text));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Copied all text to clipboard',
                      style: TextStyle(color: widget.colors.inkPrimary),
                    ),
                    backgroundColor: widget.colors.surfacePanel,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            }
          }
        },
      ),
    );
  }
}

