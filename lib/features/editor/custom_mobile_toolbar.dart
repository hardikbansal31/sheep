import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// A wrapper around [MobileToolbarWidget] that exposes the internal
/// [MobileToolbarTheme.iconColor] property, fixing an issue in AppFlowy Editor
/// where the icon color was hardcoded to Colors.black.
class ThemedMobileToolbar extends StatelessWidget {
  const ThemedMobileToolbar({
    super.key,
    required this.editorState,
    required this.toolbarItems,
    this.backgroundColor = Colors.white,
    this.foregroundColor = const Color(0xff676666),
    this.iconColor = Colors.black,
    this.clearDiagonalLineColor = const Color(0xffB3261E),
    this.itemHighlightColor = const Color(0xff1F71AC),
    this.itemOutlineColor = const Color(0xFFE3E3E3),
    this.tabbarSelectedBackgroundColor = const Color(0x23808080),
    this.tabbarSelectedForegroundColor = Colors.black,
    this.primaryColor = const Color(0xff1F71AC),
    this.onPrimaryColor = Colors.white,
    this.outlineColor = const Color(0xFFE3E3E3),
    this.toolbarHeight = 50.0,
    this.borderRadius = 6.0,
    this.buttonHeight = 40.0,
    this.buttonSpacing = 8.0,
    this.buttonBorderWidth = 1.0,
    this.buttonSelectedBorderWidth = 2.0,
  });

  final EditorState editorState;
  final List<MobileToolbarItem> toolbarItems;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color iconColor;
  final Color clearDiagonalLineColor;
  final Color itemHighlightColor;
  final Color itemOutlineColor;
  final Color tabbarSelectedBackgroundColor;
  final Color tabbarSelectedForegroundColor;
  final Color primaryColor;
  final Color onPrimaryColor;
  final Color outlineColor;
  final double toolbarHeight;
  final double borderRadius;
  final double buttonHeight;
  final double buttonSpacing;
  final double buttonBorderWidth;
  final double buttonSelectedBorderWidth;

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
            backgroundColor: backgroundColor,
            foregroundColor: foregroundColor,
            iconColor: iconColor,
            clearDiagonalLineColor: clearDiagonalLineColor,
            itemHighlightColor: itemHighlightColor,
            itemOutlineColor: itemOutlineColor,
            tabBarSelectedBackgroundColor: tabbarSelectedBackgroundColor,
            tabBarSelectedForegroundColor: tabbarSelectedForegroundColor,
            primaryColor: primaryColor,
            onPrimaryColor: onPrimaryColor,
            outlineColor: outlineColor,
            toolbarHeight: toolbarHeight,
            borderRadius: borderRadius,
            buttonHeight: buttonHeight,
            buttonSpacing: buttonSpacing,
            buttonBorderWidth: buttonBorderWidth,
            buttonSelectedBorderWidth: buttonSelectedBorderWidth,
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
