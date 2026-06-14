import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../sections/sections_pane.dart';
import '../pages/pages_pane.dart';
import '../editor/editor_pane.dart';
import 'providers.dart';

class DesktopShell extends ConsumerWidget {
  const DesktopShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final showSections = ref.watch(sectionsPaneVisibleProvider);
    final showPages = ref.watch(pagesPaneVisibleProvider);

    return Scaffold(
      body: Row(
      children: [
        // Sections pane
        _CollapsiblePane(
          visible: showSections,
          width: SectionsPane.paneWidth,
          child: const RepaintBoundary(child: SectionsPane()),
        ),
        if (showSections)
          VerticalDivider(width: 1, thickness: 1, color: colors.border),

        // Pages pane
        _CollapsiblePane(
          visible: showPages,
          width: PagesPane.paneWidth,
          child: const RepaintBoundary(child: PagesPane()),
        ),
        if (showPages)
          VerticalDivider(width: 1, thickness: 1, color: colors.border),

        // Editor (always visible)
        Expanded(
          child: RepaintBoundary(child: EditorPane(key: editorPaneKey)),
        ),
      ],
      ),
    );
  }
}

class _CollapsiblePane extends StatelessWidget {
  const _CollapsiblePane({
    required this.visible,
    required this.width,
    required this.child,
  });

  final bool visible;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: visible ? width : 0,
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      child: OverflowBox(
        alignment: Alignment.centerLeft,
        maxWidth: width,
        minWidth: width,
        child: child,
      ),
    );
  }
}
