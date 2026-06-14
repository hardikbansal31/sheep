import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

class ThemedMobileToolbar extends StatelessWidget {
  const ThemedMobileToolbar({
    super.key,
    required this.editorState,
    required this.toolbarItems,
    required this.iconColor,
  });

  final EditorState editorState;
  final List<MobileToolbarItem> toolbarItems;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Selection?>(
      valueListenable: editorState.selectionNotifier,
      builder: (_, Selection? selection, __) {
        if (selection == null) {
          return const SizedBox.shrink();
        }
        return RepaintBoundary(
          child: MobileToolbarTheme(
            iconColor: iconColor,
            child: MobileToolbarWidget(
              editorState: editorState,
              selection: selection,
              toolbarItems: toolbarItems,
            ),
          ),
        );
      },
    );
  }
}
