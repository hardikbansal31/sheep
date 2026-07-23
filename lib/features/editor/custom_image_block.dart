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
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        BlockComponentAlignMixin {
  
  @override
  final forwardKey = GlobalKey(debugLabel: 'custom_image_block');

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;

  @override
  GlobalKey<State<StatefulWidget>> blockComponentKey = GlobalKey(
    debugLabel: 'image',
  );

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
}
