import 'package:flutter/material.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_theme.dart';

class CustomCodeBlockComponentBuilder extends BlockComponentBuilder {
  CustomCodeBlockComponentBuilder({
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return CustomCodeBlockComponentWidget(
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
  BlockComponentValidate get validate => (node) => node.delta != null;
}

class CustomCodeBlockComponentWidget extends BlockComponentStatefulWidget {
  const CustomCodeBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<CustomCodeBlockComponentWidget> createState() =>
      _CustomCodeBlockComponentWidgetState();
}

class _CustomCodeBlockComponentWidgetState extends State<CustomCodeBlockComponentWidget>
    with
        SelectableMixin,
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentBackgroundColorMixin,
        BlockComponentTextDirectionMixin,
        BlockComponentAlignMixin {
  @override
  final forwardKey = GlobalKey(debugLabel: 'custom_code_rich_text');

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => widget.node.key;

  @override
  GlobalKey<State<StatefulWidget>> blockComponentKey = GlobalKey(
    debugLabel: 'code',
  );

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  @override
  late final editorState = Provider.of<EditorState>(context, listen: false);

  @override
  Widget build(BuildContext context) {
    final textDirection = calculateTextDirection(
      layoutDirection: Directionality.maybeOf(context),
    );
    final colors = AppTheme.colorsOf(context);

    // Provide a beautiful container for the monospace text
    Widget child = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfacePanel, // use panel color for code block
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border, width: 1),
      ),
      alignment: alignment,
      child: AppFlowyRichText(
        key: forwardKey,
        delegate: this,
        node: widget.node,
        editorState: editorState,
        textAlign: alignment?.toTextAlign ?? textAlign,
        placeholderText: placeholderText,
        textSpanDecorator: (textSpan) {
          // Force JetBrains Mono font
          return textSpan.updateTextStyle(
            textStyleWithTextSpan(textSpan: textSpan).copyWith(
              fontFamily: GoogleFonts.jetBrainsMono().fontFamily,
              fontSize: 13,
              height: 1.5,
              color: colors.inkPrimary,
            ),
          );
        },
        placeholderTextSpanDecorator: (textSpan) =>
            textSpan.updateTextStyle(
          placeholderTextStyleWithTextSpan(textSpan: textSpan),
        ),
        textDirection: textDirection,
        cursorColor: editorState.editorStyle.cursorColor,
        selectionColor: editorState.editorStyle.selectionColor,
        cursorWidth: editorState.editorStyle.cursorWidth,
      ),
    );

    child = Container(
      decoration: decoration,
      key: blockComponentKey,
      padding: padding,
      child: child,
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
