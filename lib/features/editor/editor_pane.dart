import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, compute;
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
import '../pages/providers.dart';
import '../sections/providers.dart';
import '../settings/providers.dart';
import '../settings/settings_state.dart';
import '../../core/auth/auth_providers.dart';
import 'custom_code_block.dart';
import 'editor_top_bar.dart';
import 'providers.dart';

Map<String, dynamic> _decodePageJson(String source) {
  return jsonDecode(source) as Map<String, dynamic>;
}

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
  StreamSubscription? _transactionSub;
  bool _hasUnsavedChanges = false;

  // Cached editor configuration — rebuilt only in _initEditorState / settings change
  Map<String, BlockComponentBuilder>? _cachedBlockBuilders;
  EditorStyle? _cachedEditorStyle;
  List<CommandShortcutEvent>? _cachedCommandShortcuts;
  List<CharacterShortcutEvent>? _cachedCharacterShortcuts;
  SettingsState? _lastCachedSettings;
  Brightness? _lastCachedBrightness;

  @override
  void initState() {
    super.initState();
    TableDefaults.colWidth = 320.0;
  }

  @override
  void dispose() {
    if (_debounceTimer?.isActive ?? false) {
      _debounceTimer!.cancel();
      if (_currentlyLoadedPageId != null && _editorState != null && _hasUnsavedChanges) {
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

    _transactionSub?.cancel();
    _editorScrollController?.dispose();
    _editorState?.dispose();
    super.dispose();
  }

  /// Builds and caches all editor configuration objects.
  /// Only called from _initEditorState and when settings/theme change.
  void _rebuildEditorCaches(SettingsState settings, Brightness brightness) {
    final colors = brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;

    _cachedBlockBuilders = {
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
                node.attributes[HeadingBlockKeys.level] as int? ?? 1;
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
    };

    _cachedEditorStyle = EditorStyle.desktop(
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
    );

    _cachedCommandShortcuts = [
      _customPasteCommand,
      ...standardCommandShortcutEvents.where(
        (e) => e.key != 'paste the content',
      ),
    ];

    _cachedCharacterShortcuts = [
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
    ];

    _lastCachedSettings = settings;
    _lastCachedBrightness = brightness;
  }

  /// Only rebuilds caches if settings or theme actually changed.
  void _ensureEditorCaches(SettingsState settings, Brightness brightness) {
    if (_cachedBlockBuilders == null ||
        _lastCachedSettings != settings ||
        _lastCachedBrightness != brightness) {
      _rebuildEditorCaches(settings, brightness);
    }
  }

  Future<void> _initEditorState(SyncPage page) async {
    // 1. Flush final save of old page before cancelling
    if (_currentlyLoadedPageId != null && _editorState != null && _hasUnsavedChanges) {
      final title = _extractTitle(_editorState!.document);
      if (title.isNotEmpty) {
        final jsonStr = jsonEncode(_editorState!.document.toJson());
        try {
          ref
              .read(syncRepoProvider)
              .updatePage(_currentlyLoadedPageId!, title, jsonStr);
        } catch (_) {}
      }
    }

    // 2. Now safe to cancel — old content is saved
    _transactionSub?.cancel();
    _transactionSub = null;
    _debounceTimer?.cancel();

    final oldEditorState = _editorState;
    final oldScrollController = _editorScrollController;
    Timer(const Duration(milliseconds: 350), () {
      oldEditorState?.dispose();
      oldScrollController?.dispose();
    });

    final jsonMap = await compute(_decodePageJson, page.contentJson);

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
      shrinkWrap: false,
    );

    _hasUnsavedChanges = false;

    _transactionSub = newEditorState.transactionStream.listen((event) {
      _hasUnsavedChanges = true;
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
            if (mounted && _currentlyLoadedPageId == page.id) {
              _hasUnsavedChanges = false;
            }
            // Don't invalidate fullPageProvider here — the editor already
            // holds the live EditorState in memory. Invalidating would trigger
            // a redundant DB re-fetch and widget rebuild every 500ms while
            // typing. fullPageProvider is only invalidated on external changes
            // (e.g. page switch, sync from another device).
          } catch (e) {
            debugPrint('Error saving page: $e');
          }
        }
      });
    });

    // Build caches with current settings before setState
    if (!mounted) return;
    final currentSettings = ref.read(settingsProvider).value ?? const SettingsState();
    _rebuildEditorCaches(currentSettings, Theme.of(context).brightness);

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
    final session = ref.watch(unlockedSessionProvider);
    final settings = ref.watch(
      settingsProvider.select((s) => s.value ?? const SettingsState()),
    );
    final isMobileWidth = MediaQuery.of(context).size.width < 760;

    Widget contentChild;

    if (activePageId == null) {
      contentChild = const Center(
        key: ValueKey('empty_state'),
        child: _EditorPlaceholder(),
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

            if (page.isLocked && !session.contains(page.id) && !session.contains(page.sectionId)) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_outline, size: 48, color: colors.inkMuted),
                    const SizedBox(height: 16),
                    Text(
                      'This page is protected',
                      style: TextStyle(color: colors.inkMuted, fontSize: 16),
                    ),
                  ],
                ),
              );
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
                child: Builder(
                  builder: (context) {
                    // Rebuild caches if settings or theme changed since last cache
                    _ensureEditorCaches(settings, Theme.of(context).brightness);

                    return AppFlowyEditor(
                      editorState: _editorState!,
                      editorScrollController: _editorScrollController!,
                      blockComponentBuilders: _cachedBlockBuilders!,
                      editorStyle: _cachedEditorStyle!,
                      commandShortcutEvents: _cachedCommandShortcuts!,
                      characterShortcutEvents: _cachedCharacterShortcuts!,
                      contextMenuBuilder:
                          (context, position, editorState, onPressed) =>
                              const SizedBox.shrink(),
                    );
                  },
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
          EditorTopBar(
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

class _EditorPlaceholder extends ConsumerStatefulWidget {
  const _EditorPlaceholder();

  @override
  ConsumerState<_EditorPlaceholder> createState() => _EditorPlaceholderState();
}

class _EditorPlaceholderState extends ConsumerState<_EditorPlaceholder> {
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
    final activeSectionId = ref.watch(activeSectionProvider);
    final hasPages = activeSectionId != null &&
        (ref.watch(pagesProvider(activeSectionId)).value?.isNotEmpty ?? false);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.edit_note_rounded, color: colors.inkMuted, size: 48),
        const SizedBox(height: AppSpacing.md),
        Text(
          hasPages
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
