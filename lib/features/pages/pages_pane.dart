import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/sync/sync_repository.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../layout/providers.dart';
import '../sections/providers.dart';
import '../settings/providers.dart';
import '../settings/settings_state.dart';
import 'providers.dart';

final _dateFormat = DateFormat('MMM d, yyyy');

class PagesPane extends ConsumerWidget {
  const PagesPane({super.key});

  static const double paneWidth = 240;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final activeSectionId = ref.watch(activeSectionProvider);

    if (activeSectionId == null) {
      return Container(
        width: paneWidth,
        color: colors.surfacePanel,
        child: Column(
          children: [
            _Header(colors: colors),
            Expanded(
              child: Center(
                child: Text(
                  'No section selected',
                  style: TextStyle(color: colors.inkMuted),
                ),
              ),
            ),
            _BottomBar(colors: colors),
          ],
        ),
      );
    }

    final pagesAsync = ref.watch(pagesProvider(activeSectionId));
    final activePageId = ref.watch(activePageProvider);

    if (pagesAsync.hasValue &&
        pagesAsync.value!.isNotEmpty &&
        activePageId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Double check activePageProvider hasn't changed before updating
        if (ref.read(activePageProvider) == null) {
          ref.read(activePageProvider.notifier).select(pagesAsync.value!.first.id);
        }
      });
    }
    return Container(
      width: paneWidth,
      color: colors.surfacePanel,
      child: Column(
        children: [
          _Header(colors: colors),
          Expanded(
            child: pagesAsync.when(
              data: (pages) => ListView.builder(
                itemCount: pages.length,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                itemBuilder: (context, index) {
                  final page = pages[index];
                  return _PageItem(
                    page: page,
                    isSelected: page.id == activePageId,
                    onTap: () =>
                        ref.read(activePageProvider.notifier).select(page.id),
                  );
                },
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(
                child: Text(
                  'Error loading pages',
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
    final uiScale = (ref.watch(settingsProvider).value ?? const SettingsState()).uiScale;
    return Container(
      height: AppSpacing.xxl,
      padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xs),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            'Pages',
            style: TextStyle(
              color: colors.inkSecondary,
              fontSize: 11 * uiScale,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.menu_outlined, color: colors.inkSecondary, size: 18),
            onPressed: () =>
                ref.read(pagesPaneVisibleProvider.notifier).toggle(),
            splashRadius: 16,
            tooltip: 'Toggle pages (Ctrl+T)',
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
          const Spacer(),
          IconButton(
            icon: Icon(Icons.add_rounded, color: colors.inkSecondary, size: 18),
            onPressed: () async {
              final activeSectionId = ref.read(activeSectionProvider);
              if (activeSectionId != null) {
                final repo = ref.read(syncRepoProvider);
                final page = await repo.createPage(activeSectionId, 'Title');
                ref.read(activePageProvider.notifier).select(page.id);
              }
            },
            splashRadius: 16,
            tooltip: 'New page (Ctrl+N)',
          ),
        ],
      ),
    );
  }
}

class _PageItem extends ConsumerWidget {
  const _PageItem({
    required this.page,
    required this.isSelected,
    required this.onTap,
  });

  final PageListEntry page;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final uiScale = (ref.watch(settingsProvider).value ?? const SettingsState()).uiScale;
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
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.red, fontSize: 14 * uiScale)),
                ),
              ],
            ).then((value) {
              if (!context.mounted) return;
              if (value == 'delete') {
                final repo = ref.read(syncRepoProvider);
                repo.softDeletePage(page.id);
                if (isSelected) {
                  ref.read(activePageProvider.notifier).select(null);
                }
                ScaffoldMessenger.of(context).clearSnackBars();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Page "${page.title}" deleted', style: TextStyle(color: colors.inkPrimary)),
                    backgroundColor: colors.surfacePanel,
                    action: SnackBarAction(
                      label: 'Undo',
                      textColor: colors.accent,
                      onPressed: () {
                        repo.restorePage(page.id);
                      },
                    ),
                    behavior: SnackBarBehavior.floating,
                    margin: const EdgeInsets.all(AppSpacing.md),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    duration: const Duration(seconds: 5),
                  ),
                );
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    page.title,
                    style: TextStyle(
                      color: isSelected ? colors.accent : colors.inkPrimary,
                      fontSize: 13 * uiScale,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    _dateFormat.format(page.updatedAt),
                    style: TextStyle(
                      color: isSelected ? colors.accent : colors.inkSecondary,
                      fontSize: 11 * uiScale,
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
