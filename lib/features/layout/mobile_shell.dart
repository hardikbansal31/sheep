import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_theme.dart';
import '../editor/editor_pane.dart';
import 'providers.dart';

/// Linear stack navigator for mobile: Sections → Pages → Editor.
class MobileShell extends ConsumerWidget {
  const MobileShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(mobileNavIndexProvider);
    final colors = AppTheme.colorsOf(context);

    return Scaffold(
      backgroundColor: colors.surfaceBase,
      appBar: AppBar(
        backgroundColor: colors.surfacePanel,
        leading: index > 0
            ? IconButton(
                icon: Icon(Icons.arrow_back_rounded, color: colors.inkPrimary),
                onPressed: () => ref.read(mobileNavIndexProvider.notifier).back(),
              )
            : null,
        title: Text(
          _titles[index],
          style: TextStyle(
            color: colors.inkSecondary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.8,
          ),
        ),
        centerTitle: false,
        elevation: 0,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _buildView(index, ref),
      ),
    );
  }

  static const _titles = ['sections', 'pages', 'editor'];

  Widget _buildView(int index, WidgetRef ref) {
    return switch (index) {
      0 => _MobileSections(
          key: const ValueKey(0),
          onTap: () => ref.read(mobileNavIndexProvider.notifier).go(1),
        ),
      1 => _MobilePages(
          key: const ValueKey(1),
          onTap: () => ref.read(mobileNavIndexProvider.notifier).go(2),
        ),
      _ => const RepaintBoundary(
          key: ValueKey(2),
          child: EditorPane(),
        ),
    };
  }
}

/// Full-width sections list for mobile.
class _MobileSections extends StatelessWidget {
  const _MobileSections({super.key, required this.onTap});
  final VoidCallback onTap;

  static const _placeholders = [
    'Getting Started',
    'Work Notes',
    'Personal',
    'Research',
    'Archive',
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return Container(
      color: colors.surfacePanel,
      child: ListView.builder(
        itemCount: _placeholders.length,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemBuilder: (context, index) {
          return ListTile(
            leading: Icon(Icons.folder_outlined,
                color: colors.inkMuted, size: 20),
            title: Text(
              _placeholders[index],
              style: TextStyle(color: colors.inkPrimary, fontSize: 14),
            ),
            trailing: Icon(Icons.chevron_right_rounded,
                color: colors.inkMuted, size: 20),
            onTap: onTap,
          );
        },
      ),
    );
  }
}

/// Full-width pages list for mobile.
class _MobilePages extends StatelessWidget {
  const _MobilePages({super.key, required this.onTap});
  final VoidCallback onTap;

  static const _placeholders = [
    ('Welcome to Sheep', 'Jun 10, 2026'),
    ('Meeting notes', 'Jun 9, 2026'),
    ('Quick ideas', 'Jun 8, 2026'),
    ('Reading list', 'Jun 7, 2026'),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    return Container(
      color: colors.surfacePanel,
      child: ListView.builder(
        itemCount: _placeholders.length,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        itemBuilder: (context, index) {
          final (title, date) = _placeholders[index];
          return ListTile(
            title: Text(
              title,
              style: TextStyle(color: colors.inkPrimary, fontSize: 14),
            ),
            subtitle: Text(
              date,
              style: TextStyle(color: colors.inkMuted, fontSize: 12),
            ),
            trailing: Icon(Icons.chevron_right_rounded,
                color: colors.inkMuted, size: 20),
            onTap: onTap,
          );
        },
      ),
    );
  }
}
