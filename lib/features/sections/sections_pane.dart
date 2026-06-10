import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/database/database.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../layout/providers.dart';
import 'providers.dart';

class SectionsPane extends ConsumerWidget {
  const SectionsPane({super.key});

  static const double paneWidth = 240;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final sectionsAsync = ref.watch(sectionsProvider);
    final activeSectionId = ref.watch(activeSectionProvider);

    ref.listen<AsyncValue<List<Section>>>(sectionsProvider, (previous, next) {
      if (next.hasValue &&
          next.value!.isNotEmpty &&
          ref.read(activeSectionProvider) == null) {
        ref.read(activeSectionProvider.notifier).select(next.value!.first.id);
      }
    });
    return Container(
      width: paneWidth,
      color: colors.surfacePanel,
      child: Column(
        children: [
          _Header(colors: colors),
          Expanded(
            child: sectionsAsync.when(
              data: (sections) => ListView.builder(
                itemCount: sections.length,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final section = sections[index];
                  return _SectionItem(
                    section: section,
                    isSelected: section.id == activeSectionId,
                    onTap: () => ref
                        .read(activeSectionProvider.notifier)
                        .select(section.id),
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Text(
                  'Error loading sections',
                  style: TextStyle(color: colors.inkMuted),
                ),
              ),
            ),
          ),
          _BottomBar(colors: colors),
        ],
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: AppSpacing.xxl,
      padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xs),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            'sections',
            style: TextStyle(
              color: colors.inkSecondary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.view_sidebar_outlined,
                color: colors.inkMuted, size: 18),
            onPressed: () =>
                ref.read(sectionsPaneVisibleProvider.notifier).toggle(),
            splashRadius: 16,
            tooltip: 'Toggle sections',
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends ConsumerWidget {
  const _BottomBar({required this.colors});
  final AppColors colors;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      height: AppSpacing.xxl,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.search_rounded, color: colors.inkMuted, size: 18),
            onPressed: () {},
            splashRadius: 16,
            tooltip: 'Search',
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.add_rounded, color: colors.inkMuted, size: 18),
            onPressed: () async {
              final section = await ref.read(repositoryProvider).createSection('New Section');
              ref.read(activeSectionProvider.notifier).select(section.id);
            },
            splashRadius: 16,
            tooltip: 'New section',
          ),
        ],
      ),
    );
  }
}

class _SectionItem extends ConsumerWidget {
  const _SectionItem({
    required this.section,
    required this.isSelected,
    required this.onTap,
  });

  final Section section;
  final bool isSelected;
  final VoidCallback onTap;

  void _showRenameDialog(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final controller = TextEditingController(text: section.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surfacePanel,
        title: Text('Rename Section', style: TextStyle(color: colors.inkPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: colors.inkPrimary),
          decoration: InputDecoration(
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: colors.border)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: colors.accent)),
          ),
          onSubmitted: (val) {
            if (val.trim().isNotEmpty) {
              ref.read(repositoryProvider).updateSectionTitle(section.id, val.trim());
            }
            Navigator.of(context).pop();
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.inkMuted)),
          ),
          TextButton(
            onPressed: () {
              final val = controller.text;
              if (val.trim().isNotEmpty) {
                ref.read(repositoryProvider).updateSectionTitle(section.id, val.trim());
              }
              Navigator.of(context).pop();
            },
            child: Text('Save', style: TextStyle(color: colors.accent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 1,
      ),
      child: Material(
        color: isSelected ? colors.surfaceHover : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: GestureDetector(
          onSecondaryTapDown: (details) {
            showMenu(
              context: context,
              position: RelativeRect.fromLTRB(
                details.globalPosition.dx,
                details.globalPosition.dy,
                details.globalPosition.dx,
                details.globalPosition.dy,
              ),
              color: colors.surfacePanel,
              items: [
                PopupMenuItem(
                  value: 'rename',
                  child: Text('Rename', style: TextStyle(color: colors.inkPrimary)),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.red)),
                ),
              ],
            ).then((value) {
              if (!context.mounted) return;
              if (value == 'rename') {
                _showRenameDialog(context, ref);
              } else if (value == 'delete') {
                ref.read(repositoryProvider).softDeleteSection(section.id);
                if (isSelected) {
                  ref.read(activeSectionProvider.notifier).select(null);
                }
              }
            });
          },
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            hoverColor: colors.surfaceHover,
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.folder_outlined,
                    color: isSelected ? colors.accent : colors.inkMuted,
                    size: 16,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      section.title,
                      style: TextStyle(
                        color: isSelected ? colors.accent : colors.inkPrimary,
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
