import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:super_clipboard/super_clipboard.dart';
import 'dart:typed_data';

import '../../core/sync/sync_repository.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/providers.dart';
import 'custom_mobile_toolbar.dart';
import '../../core/theme/app_theme.dart';
import '../layout/providers.dart';
import '../export/export_service.dart';
import '../export/markdown_exporter.dart';
import '../export/pdf_exporter.dart';
import '../pages/providers.dart';
import '../search/search_modal.dart';
import '../sections/providers.dart';
import '../settings/providers.dart';
import '../settings/settings_state.dart';
import 'custom_code_block.dart';
import 'providers.dart';
import 'spell_check_service.dart';

final GlobalKey<EditorPaneState> editorPaneKey = GlobalKey<EditorPaneState>(
  debugLabel: 'editor_pane_key',
);

class EditorPane extends ConsumerStatefulWidget {
  const EditorPane({super.key});

  @override
  ConsumerState<EditorPane> createState() => EditorPaneState();
}

class EditorPaneState extends ConsumerState<EditorPane> {
  EditorState? _editorState;
  EditorScrollController? _editorScrollController;
  Timer? _debounceTimer;
  String? _currentlyLoadedPageId;

  final Map<String, List<TextRange>> _misspelledRanges = {};
  final Map<String, List<({TextRange range, DateTime timestamp})>>
  _correctedRanges = {};
  final Map<String, Timer> _spellCheckDebouncers = {};

  @override
  void initState() {
    super.initState();
    TableDefaults.colWidth = 320.0;
  }

  @override
  void dispose() {
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
      if (_currentlyLoadedPageId != null && _editorState != null) {
        final title = _extractTitle(_editorState!.document);
        if (title.isNotEmpty) {
          final jsonStr = jsonEncode(_editorState!.document.toJson());
          try {
            ref
                .read(syncRepoProvider)
                .updatePage(_currentlyLoadedPageId!, title, jsonStr);
            ref.invalidate(fullPageProvider(_currentlyLoadedPageId!));
          } catch (_) {}
        }
      }
    }

    _editorScrollController?.dispose();
    _editorState?.dispose();
    for (final debouncer in _spellCheckDebouncers.values) {
      debouncer.cancel();
    }
    super.dispose();
  }

  void _initEditorState(SyncPage page) {
    _debounceTimer?.cancel();
    final oldEditorState = _editorState;
    final oldScrollController = _editorScrollController;
    Timer(const Duration(milliseconds: 350), () {
      oldEditorState?.dispose();
      oldScrollController?.dispose();
    });

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
              'data': {
                'delta': [
                  {'insert': page.title},
                ],
              },
            });
            children.add({
              'type': 'paragraph',
              'data': {
                'delta': [
                  {'insert': ''},
                ],
              },
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

    // Initial spellcheck for all nodes
    _spellCheckAllNodes(newEditorState.document);

    newEditorState.transactionStream.listen((event) {
      // Spellcheck on changed nodes
      for (final op in event.$2.operations) {
        if (op is UpdateTextOperation) {
          final node = newEditorState.document.nodeAtPath(op.path);
          if (node != null && node.delta != null) {
            _debounceSpellCheckForNode(node);
          }
        }
      }

      // Auto-save logic
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
        // Only save if the current loaded page is still the active one
        if (_currentlyLoadedPageId == page.id &&
            ref.read(activePageProvider) == page.id) {
          final title = _extractTitle(newEditorState.document);
          if (title.isEmpty) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Title cannot be empty. Reverting to last saved state or please provide a title.',
                ),
              ),
            );
            // Skip saving
            return;
          }

          final jsonStr = jsonEncode(newEditorState.document.toJson());
          try {
            await ref
                .read(syncRepoProvider)
                .updatePage(page.id, title, jsonStr);
            ref.invalidate(fullPageProvider(page.id));
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

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final rootChildren = newEditorState.document.root.children;
        if (rootChildren.length > 1) {
          final firstBodyNode = rootChildren[1];
          newEditorState.updateSelectionWithReason(
            Selection.collapsed(Position(path: firstBodyNode.path, offset: 0)),
            reason: SelectionUpdateReason.uiEvent,
          );
        } else if (rootChildren.isNotEmpty) {
          final titleNode = rootChildren.first;
          final length = titleNode.delta?.length ?? 0;
          newEditorState.updateSelectionWithReason(
            Selection.collapsed(Position(path: titleNode.path, offset: length)),
            reason: SelectionUpdateReason.uiEvent,
          );
        }
      }
    });
  }

  void _spellCheckAllNodes(Document document) {
    void walk(Node node) {
      if (node.delta != null) {
        _debounceSpellCheckForNode(node);
      }
      for (final child in node.children) {
        walk(child);
      }
    }

    walk(document.root);
  }

  void _debounceSpellCheckForNode(Node node) {
    final nodeId = node.id;
    _spellCheckDebouncers[nodeId]?.cancel();
    _spellCheckDebouncers[nodeId] = Timer(
      const Duration(milliseconds: 300),
      () async {
        final text = node.delta?.toPlainText() ?? '';
        final ranges = await ref
            .read(spellCheckServiceProvider)
            .checkSpelling(text);

        final previous = _misspelledRanges[nodeId] ?? [];
        final correctedList = <({TextRange range, DateTime timestamp})>[];

        // Compare previous misspelled words with current misspelled words
        final previousWords = previous
            .map((r) {
              if (r.start < 0 || r.end > text.length || r.start > r.end) {
                return '';
              }
              return text.substring(r.start, r.end);
            })
            .where((w) => w.isNotEmpty)
            .toSet();

        final currentMisspelledWords = ranges.map((r) {
          if (r.start < 0 || r.end > text.length || r.start > r.end) return '';
          return text.substring(r.start, r.end).toLowerCase();
        }).toSet();

        for (final prevWord in previousWords) {
          if (!currentMisspelledWords.contains(prevWord.toLowerCase())) {
            // Word was corrected, locate it in the current text
            final escaped = RegExp.escape(prevWord);
            final matches = RegExp(escaped).allMatches(text);
            for (final m in matches) {
              final wordRange = TextRange(start: m.start, end: m.end);
              final isStillMisspelled = ranges.any(
                (r) => r.start <= m.start && r.end >= m.end,
              );
              if (!isStillMisspelled) {
                correctedList.add((
                  range: wordRange,
                  timestamp: DateTime.now(),
                ));
              }
            }
          }
        }

        if (mounted) {
          setState(() {
            _misspelledRanges[nodeId] = ranges;
            if (correctedList.isNotEmpty) {
              _correctedRanges[nodeId] = [
                ...(_correctedRanges[nodeId] ?? []).where(
                  (item) =>
                      DateTime.now().difference(item.timestamp).inMilliseconds <
                      1500,
                ),
                ...correctedList,
              ];
              // Clear corrected highlight after 1.5s
              Timer(const Duration(milliseconds: 1500), () {
                if (mounted) {
                  setState(() {
                    _correctedRanges[nodeId]?.removeWhere(
                      (item) =>
                          DateTime.now()
                              .difference(item.timestamp)
                              .inMilliseconds >=
                          1500,
                    );
                  });
                }
              });
            }
          });
        }
      },
    );
  }

  CommandShortcutEvent get _customPasteCommand {
    return CommandShortcutEvent(
      key: 'paste the content',
      getDescription: () => AppFlowyEditorL10n.current.cmdPasteContent,
      command: !kIsWeb && Platform.isMacOS ? 'meta+v' : 'ctrl+v',
      handler: (editorState) {
        _handleCustomPaste(editorState);
        return KeyEventResult.handled;
      },
    );
  }

  void _handleCustomPaste(EditorState editorState) async {
    // 1. Try to get image from SystemClipboard
    final clipboard = SystemClipboard.instance;
    if (clipboard != null) {
      try {
        final reader = await clipboard.read();
        
        if (reader.canProvide(Formats.png)) {
          final imageBytes = await _readImageBytes(reader, Formats.png);
          if (imageBytes != null) {
            await _processPastedImage(editorState, imageBytes, 'png');
            return;
          }
        } else if (reader.canProvide(Formats.jpeg)) {
          final imageBytes = await _readImageBytes(reader, Formats.jpeg);
          if (imageBytes != null) {
            await _processPastedImage(editorState, imageBytes, 'jpg');
            return;
          }
        } else if (reader.canProvide(Formats.webp)) {
          final imageBytes = await _readImageBytes(reader, Formats.webp);
          if (imageBytes != null) {
            await _processPastedImage(editorState, imageBytes, 'webp');
            return;
          }
        }
      } catch (e) {
        debugPrint('Error reading clipboard: $e');
      }
    }

    // 2. Fall back to text processing
    final clipboardData = await AppFlowyClipboard.getData();
    final text = clipboardData.text;
    if (text != null && text.isNotEmpty) {
      final document = markdownToDocument(
        text,
        markdownParsers: const [MarkdownCodeBlockParser()],
      );
      final children = document.root.children;

      if (children.isNotEmpty) {
        final firstChild = children.first;
        final isSinglePlainTextParagraph =
            children.length == 1 &&
            firstChild.type == ParagraphBlockKeys.type &&
            (firstChild.delta == null ||
                !firstChild.delta!.any(
                  (op) => op.attributes != null && op.attributes!.isNotEmpty,
                ));

        if (isSinglePlainTextParagraph) {
          await editorState._pastePlainText(text);
        } else {
          final selection = editorState.selection;
          if (selection != null &&
              selection.isCollapsed &&
              children.length == 1 &&
              firstChild.type == ParagraphBlockKeys.type) {
            final node = editorState.getNodeAtPath(selection.end.path);
            if (node != null && node.delta != null) {
              final transaction = editorState.transaction;
              transaction.insertTextDelta(
                node,
                selection.startIndex,
                firstChild.delta!,
              );
              editorState.apply(transaction);
              return;
            }
          }
          await editorState._pasteChunked(children.toList());
        }
      }
    } else if (clipboardData.html != null) {
      await editorState._pasteHtml(clipboardData.html!);
    }
  }

  Future<Uint8List?> _readImageBytes(ClipboardReader reader, SimpleFileFormat format) async {
    final completer = Completer<Uint8List?>();
    reader.getFile(format, (file) {
      final stream = file.getStream();
      final chunks = <int>[];
      stream.listen(
        (data) => chunks.addAll(data),
        onDone: () => completer.complete(Uint8List.fromList(chunks)),
        onError: (e) => completer.complete(null),
      );
    });
    return completer.future;
  }

  Future<void> _processPastedImage(EditorState editorState, Uint8List bytes, String extension) async {
    try {
      final imageService = ref.read(imageServiceProvider);
      // Save locally
      final localPath = await imageService.saveImageLocally(bytes, extension: extension);
      
      // Insert image node at cursor
      final selection = editorState.selection;
      if (selection == null) return;
      
      final transaction = editorState.transaction;
      final imageNode = Node(
        type: ImageBlockKeys.type,
        attributes: {
          ImageBlockKeys.url: localPath,
        },
      );
      transaction.insertNode(selection.end.path, imageNode);
      editorState.apply(transaction);

      // Begin background upload
      ref.read(imageUploadCountProvider.notifier).increment();
      final remoteUrl = await imageService.uploadImage(localPath);
      ref.read(imageUploadCountProvider.notifier).decrement();

      // If successful, update the URL in the document
      if (remoteUrl != null && mounted) {
        _updateImageNodeUrl(editorState, localPath, remoteUrl);
      }
    } catch (e) {
      debugPrint('Error pasting image: $e');
      ref.read(imageUploadCountProvider.notifier).decrement();
    }
  }

  void _updateImageNodeUrl(EditorState editorState, String oldUrl, String newUrl) {
    void walk(Node node) {
      if (node.type == ImageBlockKeys.type && node.attributes[ImageBlockKeys.url] == oldUrl) {
        final transaction = editorState.transaction;
        transaction.updateNode(node, {ImageBlockKeys.url: newUrl});
        editorState.apply(transaction);
        return;
      }
      for (final child in node.children) {
        walk(child);
      }
    }
    walk(editorState.document.root);
  }

  String _extractTitle(Document document) {
    if (document.root.children.isEmpty) return '';
    final firstNode = document.root.children.first;
    final delta = firstNode.delta;
    return delta?.toPlainText().trim() ?? '';
  }

  void applyBlockType(String type) {
    final state = _editorState;
    if (state == null) return;
    final selection = state.selection;
    if (selection == null) return;

    if (type.startsWith('heading')) {
      final level = int.parse(type.substring(7));
      state.formatNode(
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
      state.formatNode(
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
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final activePageId = ref.watch(activePageProvider);
    final activeSectionId = ref.watch(activeSectionProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final settings = settingsAsync.value ?? const SettingsState();
    final isMobileWidth = MediaQuery.of(context).size.width < 760;

    Widget contentChild;

    if (activePageId == null) {
      final hasPages =
          activeSectionId != null &&
          (ref.watch(pagesProvider(activeSectionId)).value?.isNotEmpty ??
              false);

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
            if (page == null) {
              return const Center(child: Text('Page not found'));
            }

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
              child: Padding(
                padding: isMobileWidth
                    ? const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 24.0,
                      ).copyWith(top: 0)
                    : const EdgeInsets.symmetric(
                        horizontal: 60.0,
                        vertical: 40.0,
                      ).copyWith(top: 0),
                child: AppFlowyEditor(
                  editorState: _editorState!,
                  editorScrollController: _editorScrollController!,
                  blockComponentBuilders: {
                    ...standardBlockComponentBuilderMap,
                    'title': HeadingBlockComponentBuilder(
                      configuration: BlockComponentConfiguration(
                        padding: (node) =>
                            const EdgeInsets.only(top: 32.0, bottom: 16.0),
                      ),
                      textStyleBuilder: (level) => GoogleFonts.getFont(
                        settings.fontTitle,
                        fontSize: settings.defaultFontSize * 2.25,
                        fontWeight: FontWeight.bold,
                        color: colors.accent,
                        height: 1.2,
                      ),
                    ),
                    HeadingBlockKeys.type: HeadingBlockComponentBuilder(
                      configuration: BlockComponentConfiguration(
                        padding: (node) {
                          final level =
                              node.attributes[HeadingBlockKeys.level] as int? ??
                              1;
                          return EdgeInsets.only(
                            top: 28.0 - (level * 2),
                            bottom: 8.0,
                          );
                        },
                      ),
                      textStyleBuilder: (level) => GoogleFonts.getFont(
                        settings.fontHeadings,
                        fontSize: settings.defaultFontSize *
                            (level == 1
                                ? 1.75
                                : level == 2
                                ? 1.5
                                : level == 3
                                ? 1.25
                                : 1.125),
                        fontWeight: FontWeight.w700,
                        color: colors.inkPrimary,
                        height: 1.3,
                      ),
                    ),
                    TableBlockKeys.type: TableBlockComponentBuilder(
                      configuration: BlockComponentConfiguration(
                        padding: (node) =>
                            const EdgeInsets.symmetric(vertical: 16.0),
                        indentPadding: (node, dir) => EdgeInsets.zero,
                      ),
                      tableStyle: const TableStyle(colWidth: 320),
                    ),
                    'code': CustomCodeBlockComponentBuilder(
                      configuration: BlockComponentConfiguration(
                        padding: (node) =>
                            const EdgeInsets.symmetric(vertical: 8.0),
                      ),
                    ),
                  },
                  editorStyle: EditorStyle.desktop(
                    padding: EdgeInsets.zero,
                    cursorColor: colors.accent,
                    selectionColor: colors.accent.withValues(alpha: 0.2),
                    textStyleConfiguration: TextStyleConfiguration(
                      text: GoogleFonts.getFont(
                        settings.fontParagraph,
                        fontSize: settings.defaultFontSize,
                        color: colors.inkPrimary,
                        height: 1.5,
                      ),
                      code: GoogleFonts.getFont(
                        settings.fontCode,
                        fontSize: settings.defaultFontSize * 0.9,
                        color: colors.inkPrimary,
                        backgroundColor: colors.surfacePanel,
                        height: 1.5,
                      ),
                    ),
                  ),
                  commandShortcutEvents: [
                    _customPasteCommand,
                    ...standardCommandShortcutEvents.where(
                      (e) => e.key != 'paste the content',
                    ),
                  ],
                  characterShortcutEvents: [
                    ...standardCharacterShortcutEvents.where(
                      (e) => e != slashCommand,
                    ),
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
                  contextMenuBuilder:
                      (context, position, editorState, onPressed) =>
                          const SizedBox.shrink(),
                ),
              ),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, stack) => Center(child: Text('Error: $err')),
        ),
      );
    }

    return Container(
      color: colors.surfaceBase,
      child: Column(
        children: [
          _TopBar(
            colors: colors,
            editorState: activePageId == null ? null : _editorState,
            settings: settings,
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: contentChild,
            ),
          ),
          if (isMobileWidth && _editorState != null)
            ThemedMobileToolbar(
              editorState: _editorState!,
              backgroundColor: colors.surfacePanel,
              foregroundColor: colors.accent,
              iconColor: colors.accent,
              clearDiagonalLineColor: const Color(0xFFCF6679),
              itemHighlightColor: colors.accent,
              itemOutlineColor: colors.border,
              tabbarSelectedBackgroundColor: colors.surfaceHover,
              tabbarSelectedForegroundColor: colors.accent,
              primaryColor: colors.accent,
              onPrimaryColor: colors.surfaceBase,
              outlineColor: colors.border,
              toolbarItems: [
                textDecorationMobileToolbarItem,
                listMobileToolbarItem,
                todoListMobileToolbarItem,
                headingMobileToolbarItem,
                linkMobileToolbarItem,
                quoteMobileToolbarItem,
                codeMobileToolbarItem,
              ],
            ),
        ],
      ),
    );
  }
}

class _TopBar extends ConsumerStatefulWidget {
  const _TopBar({
    required this.colors,
    required this.editorState,
    required this.settings,
  });
  final AppColors colors;
  final EditorState? editorState;
  final SettingsState settings;

  @override
  ConsumerState<_TopBar> createState() => _TopBarState();
}

class _TopBarState extends ConsumerState<_TopBar> {
  String _currentBlockType = ParagraphBlockKeys.type;
  late String _currentFontFamily = widget.settings.fontParagraph;
  late double _currentFontSize = widget.settings.defaultFontSize;
  bool _isCollapsed = false;

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
        final knownTypes = {
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

      setState(() {
        _currentFontFamily = toggledFont != null
            ? _reverseResolveGoogleFont(toggledFont)
            : widget.settings.fontParagraph;
        _currentFontSize = toggledSize ?? widget.settings.defaultFontSize;
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

            fontFamilies.add(
              font != null
                  ? _reverseResolveGoogleFont(font)
                  : widget.settings.fontParagraph,
            );
            fontSizes.add(size ?? widget.settings.defaultFontSize);
          }
          currentOffset += op.length;
        }
      }

      setState(() {
        if (fontFamilies.isEmpty) {
          _currentFontFamily = widget.settings.fontParagraph;
        } else if (fontFamilies.length == 1) {
          _currentFontFamily = fontFamilies.first;
        } else {
          _currentFontFamily = 'Variable';
        }

        if (fontSizes.isEmpty) {
          _currentFontSize = widget.settings.defaultFontSize;
        } else if (fontSizes.length == 1) {
          _currentFontSize = fontSizes.first;
        } else {
          _currentFontSize = -1.0; // special value for Variable
        }
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
    const displayNames = [
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
                    DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _currentBlockType,
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: colors.inkMuted,
                          size: 16,
                        ),
                        style: TextStyle(
                          color: colors.inkPrimary,
                          fontSize: 13,
                          fontFamily: 'Inter',
                        ),
                        items: [
                          DropdownMenuItem(
                            value: ParagraphBlockKeys.type,
                            child: const Text('Normal text'),
                          ),
                          const DropdownMenuItem(
                            value: 'heading1',
                            child: Text('Heading 1'),
                          ),
                          const DropdownMenuItem(
                            value: 'heading2',
                            child: Text('Heading 2'),
                          ),
                          const DropdownMenuItem(
                            value: 'heading3',
                            child: Text('Subheading'),
                          ),
                          DropdownMenuItem(
                            value: BulletedListBlockKeys.type,
                            child: const Text('Bulleted list'),
                          ),
                          DropdownMenuItem(
                            value: NumberedListBlockKeys.type,
                            child: const Text('Numbered list'),
                          ),
                          DropdownMenuItem(
                            value: TodoListBlockKeys.type,
                            child: const Text('Checklist'),
                          ),
                          DropdownMenuItem(
                            value: QuoteBlockKeys.type,
                            child: const Text('Quote'),
                          ),
                          const DropdownMenuItem(
                            value: 'code',
                            child: Text('Code block'),
                          ),
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
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: colors.inkMuted,
                          size: 16,
                        ),
                        style: TextStyle(
                          color: colors.inkPrimary,
                          fontSize: 13,
                          fontFamily: 'Inter',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Variable',
                            child: Text('Multiple fonts'),
                          ),
                          DropdownMenuItem(
                            value: 'Inter',
                            child: Text('Inter'),
                          ),
                          DropdownMenuItem(
                            value: 'Merriweather',
                            child: Text('Merriweather'),
                          ),
                          DropdownMenuItem(
                            value: 'JetBrains Mono',
                            child: Text('JetBrains Mono'),
                          ),
                          DropdownMenuItem(
                            value: 'Roboto',
                            child: Text('Roboto'),
                          ),
                          DropdownMenuItem(
                            value: 'Open Sans',
                            child: Text('Open Sans'),
                          ),
                          DropdownMenuItem(value: 'Lato', child: Text('Lato')),
                          DropdownMenuItem(
                            value: 'Poppins',
                            child: Text('Poppins'),
                          ),
                          DropdownMenuItem(
                            value: 'Montserrat',
                            child: Text('Montserrat'),
                          ),
                          DropdownMenuItem(
                            value: 'Playfair Display',
                            child: Text('Playfair Display'),
                          ),
                          DropdownMenuItem(
                            value: 'Source Code Pro',
                            child: Text('Source Code Pro'),
                          ),
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
                        icon: Icon(
                          Icons.arrow_drop_down,
                          color: colors.inkMuted,
                          size: 16,
                        ),
                        style: TextStyle(
                          color: colors.inkPrimary,
                          fontSize: 13,
                          fontFamily: 'Inter',
                        ),
                        items:
                            [
                              -1.0,
                              10.0,
                              11.0,
                              12.0,
                              13.0,
                              14.0,
                              16.0,
                              18.0,
                              20.0,
                              24.0,
                              28.0,
                              32.0,
                              36.0,
                              48.0,
                            ].map((size) {
                              if (size == -1.0) {
                                return const DropdownMenuItem(
                                  value: -1.0,
                                  child: Text('Multiple'),
                                );
                              }
                              return DropdownMenuItem(
                                value: size,
                                child: Text('${size.toInt()}'),
                              );
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
          if (editorState != null) _exportBtn(),

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
    return PopupMenuButton<String>(
      icon: Icon(Icons.ios_share, color: widget.colors.inkSecondary, size: 18),
      tooltip: 'Export (PDF: Ctrl+P)',
      color: widget.colors.surfacePanel,
      onSelected: (value) async {
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
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'markdown',
          child: Text(
            'Export as Markdown',
            style: TextStyle(color: widget.colors.inkPrimary),
          ),
        ),
        PopupMenuItem(
          value: 'pdf',
          child: Text(
            'Export as PDF',
            style: TextStyle(color: widget.colors.inkPrimary),
          ),
        ),
      ],
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
          widget.hasPages
              ? 'Select a page or create a new one'
              : "Click '+' to get started",
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

final RegExp _hrefRegex = RegExp(
  r'https?://(?:www\.)?[a-zA-Z0-9\-\.]+\.[a-zA-Z]{2,}(?:/[^\s]*)?',
);

final RegExp _phoneRegex = RegExp(r'^\+?(?:[0-9][\s-.]?)+[0-9]$');

extension _SheepEditorPaste on EditorState {
  Future<bool> _pasteHtml(String html) async {
    final nodes = htmlToDocument(html).root.children.toList();
    // remove the front and back empty line
    while (nodes.isNotEmpty &&
        nodes.first.delta?.isEmpty == true &&
        nodes.first.children.isEmpty) {
      nodes.removeAt(0);
    }
    while (nodes.isNotEmpty &&
        nodes.last.delta?.isEmpty == true &&
        nodes.last.children.isEmpty) {
      nodes.removeLast();
    }
    if (nodes.isEmpty) {
      return false;
    }
    if (nodes.length == 1) {
      await pasteSingleLineNode(nodes.first);
    } else {
      await _pasteChunked(nodes.toList());
    }
    return true;
  }

  Future<void> _pasteChunked(List<Node> nodes) async {
    await pasteMultiLineNodes(nodes);
  }

  Future<void> _pastePlainText(String plainText) async {
    final selectionAttributes = getDeltaAttributesInSelectionStart();
    final selection = await deleteSelectionIfNeeded();

    if (selection == null) {
      return;
    }

    if (await _maybeConvertToUrlOrPhone(plainText)) {
      return;
    }

    final nodes = plainText
        .split('\n')
        .map(
          (paragraph) => paragraph
            ..replaceAll(r'\r', '')
            ..trimRight(),
        )
        .map((paragraph) {
          Delta delta = Delta();
          if (_hrefRegex.hasMatch(paragraph) ||
              _phoneRegex.hasMatch(paragraph)) {
            final match =
                _hrefRegex.firstMatch(paragraph) ??
                _phoneRegex.firstMatch(paragraph);
            if (match != null) {
              int startPos = match.start;
              int endPos = match.end;
              final String? entity = match.group(0);
              if (entity != null) {
                /// insert the text before the link or phone
                if (startPos > 0) {
                  delta.insert(paragraph.substring(0, startPos));
                }

                /// insert the link or phone
                delta.insert(
                  paragraph.substring(startPos, endPos),
                  attributes: {
                    AppFlowyRichTextKeys.href: _phoneRegex.hasMatch(entity)
                        ? 'tel:$entity'
                        : entity,
                  },
                );

                /// insert the text after the link or phone
                if (endPos < paragraph.length) {
                  delta.insert(paragraph.substring(endPos));
                }
              }
            }
          } else {
            delta.insert(paragraph, attributes: selectionAttributes);
          }
          return delta;
        })
        .map((paragraph) => paragraphNode(delta: paragraph))
        .toList();

    if (nodes.isEmpty) {
      return;
    }
    if (nodes.length == 1) {
      await pasteSingleLineNode(nodes.first);
    } else {
      await _pasteChunked(nodes.toList());
    }
  }

  Future<bool> _maybeConvertToUrlOrPhone(String plainText) async {
    final selection = this.selection;
    if (selection == null ||
        !selection.isSingle ||
        selection.isCollapsed ||
        (!_hrefRegex.hasMatch(plainText) && !_phoneRegex.hasMatch(plainText))) {
      return false;
    }

    final node = getNodeAtPath(selection.start.path);
    if (node == null) {
      return false;
    }

    final transaction = this.transaction;
    final isPhone = _phoneRegex.hasMatch(plainText);
    transaction.formatText(node, selection.startIndex, selection.length, {
      AppFlowyRichTextKeys.href: isPhone ? 'tel:$plainText' : plainText,
    });
    await apply(transaction);
    return true;
  }
}

class MarkdownCodeBlockParser extends CustomMarkdownParser {
  const MarkdownCodeBlockParser();

  @override
  List<Node> transform(
    md.Node element,
    List<CustomMarkdownParser> parsers, {
    MarkdownListType listType = MarkdownListType.unknown,
    int? startNumber,
  }) {
    if (element is! md.Element) return [];
    if (element.tag != 'pre') return [];

    final codeElement = element.children?.firstWhere(
      (child) => child is md.Element && child.tag == 'code',
      orElse: () => md.Text(''),
    );

    if (codeElement != null && codeElement is md.Element) {
      final textContent = codeElement.textContent;
      return [
        Node(
          type: 'code',
          attributes: {
            'delta': (Delta()..insert(textContent)).toJson(),
          },
        )
      ];
    }
    return [];
  }
}
