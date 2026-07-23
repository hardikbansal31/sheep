import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';

class CustomImageBlockComponentBuilder extends BlockComponentBuilder {
  CustomImageBlockComponentBuilder({
    super.configuration,
  });

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return CustomImageBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => true;
}

class CustomImageBlockComponentWidget extends BlockComponentStatefulWidget {
  const CustomImageBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<CustomImageBlockComponentWidget> createState() =>
      _CustomImageBlockComponentWidgetState();
}

class _CustomImageBlockComponentWidgetState extends State<CustomImageBlockComponentWidget>
    with
        SelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        BlockComponentAlignMixin {
  
  final imageKey = GlobalKey(debugLabel: 'custom_image_block');
  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late final editorState = Provider.of<EditorState>(context, listen: false);

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final url = widget.node.attributes[ImageBlockKeys.url] as String?;

    if (url == null || url.isEmpty) {
      return const SizedBox.shrink();
    }

    Widget imageWidget;
    
    // Check if network URL
    if (url.startsWith('http://') || url.startsWith('https://')) {
      imageWidget = CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.contain,
        placeholder: (context, url) => AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: colors.surfacePanel,
          ),
        ),
        errorWidget: (context, url, error) => AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: colors.surfacePanel,
            child: Icon(Icons.broken_image, color: colors.inkSecondary),
          ),
        ),
      );
    } else {
      // Local file
      imageWidget = Image.file(
        File(url),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: colors.surfacePanel,
            child: Icon(Icons.broken_image, color: colors.inkSecondary),
          ),
        ),
      );
    }

    Widget child = GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  Navigator.of(context).maybePop();
                },
              },
              child: Focus(
                autofocus: true,
                child: Scaffold(
                  backgroundColor: Colors.black,
                  body: Stack(
                    children: [
                      Positioned.fill(
                        child: InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: Center(
                            child: Hero(
                              tag: node.id,
                              child: imageWidget,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 16,
                        right: 16,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 32),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            fullscreenDialog: true,
          ),
        );
      },
      child: Hero(
        tag: node.id,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Container(
            key: imageKey,
            alignment: alignment,
            child: imageWidget,
          ),
        ),
      ),
    );
    
    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [
        BlockSelectionType.block,
      ],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }

    return child;
  }

  @override
  Position start() => Position(path: widget.node.path, offset: 0);

  @override
  Position end() => Position(path: widget.node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({
    bool shiftWithBaseOffset = false,
  }) {
    final imageBox = imageKey.currentContext?.findRenderObject();
    if (imageBox is RenderBox) {
      return Offset.zero & imageBox.size;
    }
    return Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) {
      return null;
    }
    final size = _renderBox!.size;
    return Rect.fromLTWH(-size.width / 2.0, 0, size.width, size.height);
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    if (_renderBox == null) {
      return [];
    }
    final parentBox = context.findRenderObject();
    final imageBox = imageKey.currentContext?.findRenderObject();
    if (parentBox is RenderBox && imageBox is RenderBox) {
      return [
        imageBox.localToGlobal(Offset.zero, ancestor: parentBox) &
            imageBox.size,
      ];
    }
    return [Offset.zero & _renderBox!.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) => Selection.single(
        path: widget.node.path,
        startOffset: 0,
        endOffset: 1,
      );

  @override
  Offset localToGlobal(
    Offset offset, {
    bool shiftWithBaseOffset = false,
  }) =>
      _renderBox!.localToGlobal(offset);
}
