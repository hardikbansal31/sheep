import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import 'providers.dart';

class TrashModal extends ConsumerWidget {
  const TrashModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final isMobileWidth = MediaQuery.of(context).size.width < 760;

    if (isMobileWidth) {
      return Dialog.fullscreen(
        backgroundColor: colors.surfaceBase,
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
            child: const _TrashContent(isMobileWidth: true),
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: colors.surfaceBase,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 500,
        constraints: const BoxConstraints(maxHeight: 650),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: const _TrashContent(isMobileWidth: false),
      ),
    );
  }
}

class _TrashContent extends ConsumerStatefulWidget {
  const _TrashContent({required this.isMobileWidth});
  final bool isMobileWidth;

  @override
  ConsumerState<_TrashContent> createState() => _TrashContentState();
}

class _TrashContentState extends ConsumerState<_TrashContent> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _emptyTrash(AppColors colors) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surfacePanel,
        title: Text('Empty Trash?', style: TextStyle(color: colors.inkPrimary)),
        content: Text(
          'This will permanently delete all items in the trash. This action cannot be undone.',
          style: TextStyle(color: colors.inkPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel', style: TextStyle(color: colors.inkMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Empty Trash', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(syncRepoProvider).emptyTrash();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Trash emptied successfully', style: TextStyle(color: colors.inkPrimary)),
            backgroundColor: colors.surfacePanel,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (widget.isMobileWidth) ...[
              IconButton(
                icon: Icon(Icons.arrow_back, color: colors.inkPrimary),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              'Trash Bin',
              style: TextStyle(
                color: colors.inkPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => _emptyTrash(colors),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('Empty Trash'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        TabBar(
          controller: _tabController,
          indicatorColor: colors.accent,
          labelColor: colors.accent,
          unselectedLabelColor: colors.inkSecondary,
          dividerColor: colors.inkMuted,
          tabs: const [
            Tab(text: 'Sections'),
            Tab(text: 'Pages'),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _DeletedSectionsView(colors: colors),
              _DeletedPagesView(colors: colors),
            ],
          ),
        ),
      ],
    );
  }
}

class _DeletedSectionsView extends ConsumerWidget {
  const _DeletedSectionsView({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deletedSectionsAsync = ref.watch(deletedSectionsProvider);

    return deletedSectionsAsync.when(
      data: (sections) {
        if (sections.isEmpty) {
          return _EmptyTrashState(colors: colors, message: 'No deleted sections');
        }
        return ListView.separated(
          itemCount: sections.length,
          separatorBuilder: (context, index) => Divider(color: colors.inkMuted, height: 1),
          itemBuilder: (context, index) {
            final section = sections[index];
            return ListTile(
              title: Text(section.title.isEmpty ? 'Untitled Section' : section.title,
                  style: TextStyle(color: colors.inkPrimary)),
              subtitle: Text('Restoring this section will restore its pages.',
                  style: TextStyle(color: colors.inkMuted, fontSize: 12)),
              trailing: _ActionButtons(
                colors: colors,
                onRestore: () => ref.read(syncRepoProvider).restoreSection(section.id),
                onDelete: () => ref.read(syncRepoProvider).deleteSection(section.id),
                itemName: section.title,
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error loading sections', style: TextStyle(color: colors.inkPrimary))),
    );
  }
}

class _DeletedPagesView extends ConsumerWidget {
  const _DeletedPagesView({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deletedPagesAsync = ref.watch(deletedPagesProvider);

    return deletedPagesAsync.when(
      data: (pages) {
        if (pages.isEmpty) {
          return _EmptyTrashState(colors: colors, message: 'No deleted pages');
        }
        return ListView.separated(
          itemCount: pages.length,
          separatorBuilder: (context, index) => Divider(color: colors.inkMuted, height: 1),
          itemBuilder: (context, index) {
            final page = pages[index];
            return ListTile(
              title: Text(page.title.isEmpty ? 'Untitled Page' : page.title,
                  style: TextStyle(color: colors.inkPrimary)),
              trailing: _ActionButtons(
                colors: colors,
                onRestore: () => ref.read(syncRepoProvider).restorePage(page.id),
                onDelete: () => ref.read(syncRepoProvider).deletePage(page.id),
                itemName: page.title,
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error loading pages', style: TextStyle(color: colors.inkPrimary))),
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.colors,
    required this.onRestore,
    required this.onDelete,
    required this.itemName,
  });

  final AppColors colors;
  final VoidCallback onRestore;
  final VoidCallback onDelete;
  final String itemName;

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surfacePanel,
        title: Text('Permanently delete?', style: TextStyle(color: colors.inkPrimary)),
        content: Text(
          'Delete "$itemName" permanently? This cannot be undone.',
          style: TextStyle(color: colors.inkPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.inkMuted)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onDelete();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.restore, color: colors.accent),
          tooltip: 'Restore',
          splashRadius: 20,
          onPressed: onRestore,
        ),
        IconButton(
          icon: const Icon(Icons.delete_forever, color: Colors.red),
          tooltip: 'Delete Permanently',
          splashRadius: 20,
          onPressed: () => _confirmDelete(context),
        ),
      ],
    );
  }
}

class _EmptyTrashState extends StatelessWidget {
  const _EmptyTrashState({required this.colors, required this.message});
  final AppColors colors;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline, size: 48, color: colors.inkMuted),
          const SizedBox(height: AppSpacing.md),
          Text(message, style: TextStyle(color: colors.inkMuted)),
        ],
      ),
    );
  }
}
