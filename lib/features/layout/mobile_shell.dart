import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../editor/editor_pane.dart';
import '../pages/providers.dart';
import '../sections/providers.dart';
import '../settings/settings_modal.dart';
import '../sync/sync_status_dot.dart';
import 'providers.dart';
import '../../core/auth/auth_providers.dart';
import '../auth/desktop_pin_modal.dart';

class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key});

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell> {
  int _previousIndex = 0;

  @override
  Widget build(BuildContext context) {
    final index = ref.watch(mobileNavIndexProvider);
    final colors = AppTheme.colorsOf(context);

    final isForward = index >= _previousIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _previousIndex = index;
    });

    Widget activeBody;
    switch (index) {
      case 0:
        activeBody = _MobileSections(
          key: const ValueKey(0),
          onTap: () => ref.read(mobileNavIndexProvider.notifier).go(1),
        );
        break;
      case 1:
        activeBody = _MobilePages(
          key: const ValueKey(1),
          onTap: () => ref.read(mobileNavIndexProvider.notifier).go(2),
        );
        break;
      case 2:
      default:
        activeBody = SafeArea(
          key: const ValueKey(2),
          bottom: false,
          child: RepaintBoundary(
            child: EditorPane(key: editorPaneKey),
          ),
        );
        break;
    }

    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        ref.read(mobileNavIndexProvider.notifier).back();
      },
      child: Scaffold(
        backgroundColor: colors.surfaceBase,
      appBar: index == 2 ? null : AppBar(
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
        actions: [
          const _LockResetButton(),
          if (index == 0) ...[
            IconButton(
              icon: Icon(Icons.settings_outlined, color: colors.inkSecondary),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const SettingsModal(),
                );
              },
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8.0),
              child: SyncStatusDot(),
            ),
          ],
          if (index == 0)
            IconButton(
              icon: Icon(Icons.add_rounded, color: colors.inkPrimary),
              onPressed: () async {
                final section = await ref.read(syncRepoProvider).createSection('New Section');
                ref.read(activePageProvider.notifier).select(null);
                ref.read(activeSectionProvider.notifier).select(section.id);
                ref.read(mobileNavIndexProvider.notifier).go(1);
              },
            ),
          if (index == 1)
            IconButton(
              icon: Icon(Icons.add_rounded, color: colors.inkPrimary),
              onPressed: () async {
                final activeSectionId = ref.read(activeSectionProvider);
                if (activeSectionId != null) {
                  final page = await ref.read(syncRepoProvider).createPage(activeSectionId, 'Title');
                  ref.read(activePageProvider.notifier).select(page.id);
                  ref.read(mobileNavIndexProvider.notifier).go(2);
                }
              },
            ),
        ],
      ),
        body: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final isEntering = child.key == ValueKey(index);
            
            final beginOffset = isEntering
                ? Offset(isForward ? 1.0 : -1.0, 0.0)
                : Offset(isForward ? -1.0 : 1.0, 0.0);

            final slideAnimation = Tween<Offset>(
              begin: beginOffset,
              end: Offset.zero,
            ).animate(animation);

            return SlideTransition(
              position: slideAnimation,
              child: child,
            );
          },
          child: activeBody,
        ),
      ),
    );
  }

  static const _titles = ['Sections', 'Pages', 'Editor'];
}

/// Full-width sections list for mobile.
class _MobileSections extends ConsumerWidget {
  const _MobileSections({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final sectionsAsync = ref.watch(sectionsProvider);

    return Container(
      color: colors.surfacePanel,
      child: sectionsAsync.when(
        data: (sections) {
          if (sections.isEmpty) {
            return Center(
              child: Text('No sections', style: TextStyle(color: colors.inkMuted)),
            );
          }
          return ListView.builder(
            itemCount: sections.length,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemBuilder: (context, index) {
              final section = sections[index];
              return ListTile(
                leading: Icon(section.isLocked ? Icons.lock_outline : Icons.folder_outlined, color: colors.inkMuted, size: 20),
                title: Text(
                  section.title,
                  style: TextStyle(color: colors.inkPrimary, fontSize: 14),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: colors.inkMuted, size: 20),
                onTap: () async {
                  if (section.isLocked) {
                    final session = ref.read(unlockedSessionProvider);
                    if (!session.contains(section.id)) {
                      final unlocked = await promptUnlock(context, ref, section.id);
                      if (!unlocked) return;
                    }
                  }
                  ref.read(activeSectionProvider.notifier).select(section.id);
                  onTap();
                },
                onLongPress: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: colors.surfacePanel,
                    builder: (context) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: Icon(section.isLocked ? Icons.lock_open : Icons.lock_outline, color: colors.inkPrimary),
                            title: Text(section.isLocked ? 'Disable Protection' : 'Enable Protection', style: TextStyle(color: colors.inkPrimary)),
                            onTap: () async {
                              Navigator.pop(context);
                              final success = await promptUnlock(context, ref, section.id);
                              if (!success) return;
                              ref.read(syncRepoProvider).updateSectionLock(section.id, !section.isLocked);
                            },
                          ),
                          ListTile(
                            leading: Icon(Icons.edit, color: colors.inkPrimary),
                            title: Text('Rename', style: TextStyle(color: colors.inkPrimary)),
                            onTap: () async {
                              Navigator.pop(context);
                              final ctrl = TextEditingController(text: section.title);
                              final newTitle = await showDialog<String>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: colors.surfacePanel,
                                  title: Text('Rename Section', style: TextStyle(color: colors.inkPrimary)),
                                  content: TextField(
                                    controller: ctrl,
                                    autofocus: true,
                                    style: TextStyle(color: colors.inkPrimary),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: colors.surfaceBase,
                                      border: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text('Cancel', style: TextStyle(color: colors.inkMuted)),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, ctrl.text),
                                      child: Text('Rename', style: TextStyle(color: colors.accent)),
                                    ),
                                  ],
                                ),
                              );
                              if (newTitle != null && newTitle.isNotEmpty) {
                                await ref.read(syncRepoProvider).updateSectionTitle(section.id, newTitle);
                              }
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.delete, color: Color(0xFFCF6679)),
                            title: const Text('Delete', style: TextStyle(color: Color(0xFFCF6679))),
                            onTap: () async {
                              Navigator.pop(context);
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: colors.surfacePanel,
                                  title: Text('Delete Section?', style: TextStyle(color: colors.inkPrimary)),
                                  content: Text('This will delete all pages inside it.', style: TextStyle(color: colors.inkPrimary)),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: Text('Cancel', style: TextStyle(color: colors.inkMuted)),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('Delete', style: TextStyle(color: Color(0xFFCF6679))),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await ref.read(syncRepoProvider).deleteSection(section.id);
                                if (ref.read(activeSectionProvider) == section.id) {
                                  ref.read(activeSectionProvider.notifier).select(null);
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text('Error loading sections', style: TextStyle(color: colors.inkMuted)),
        ),
      ),
    );
  }
}

/// Full-width pages list for mobile.
class _MobilePages extends ConsumerWidget {
  const _MobilePages({super.key, required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final activeSectionId = ref.watch(activeSectionProvider);

    if (activeSectionId == null) {
      return Container(
        color: colors.surfacePanel,
        child: Center(
          child: Text('No section selected', style: TextStyle(color: colors.inkMuted)),
        ),
      );
    }

    final pagesAsync = ref.watch(pagesProvider(activeSectionId));

    return Container(
      color: colors.surfacePanel,
      child: pagesAsync.when(
        data: (pages) {
          if (pages.isEmpty) {
            return Center(
              child: Text('No pages', style: TextStyle(color: colors.inkMuted)),
            );
          }
          return ListView.builder(
            itemCount: pages.length,
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            itemBuilder: (context, index) {
              final page = pages[index];
              return ListTile(
                title: Row(
                  children: [
                    if (page.isLocked) ...[
                      Icon(Icons.lock_outline, size: 14, color: colors.inkMuted),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        page.title,
                        style: TextStyle(color: colors.inkPrimary, fontSize: 14),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                subtitle: Text(
                  DateFormat('MMM d, yyyy').format(page.updatedAt),
                  style: TextStyle(color: colors.inkMuted, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: colors.inkMuted, size: 20),
                onTap: () async {
                  if (page.isLocked) {
                    final session = ref.read(unlockedSessionProvider);
                    if (!session.contains(page.id) && !session.contains(page.sectionId)) {
                      final unlocked = await promptUnlock(context, ref, page.id);
                      if (!unlocked) return;
                    }
                  }
                  ref.read(activePageProvider.notifier).select(page.id);
                  onTap();
                },
                onLongPress: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: colors.surfacePanel,
                    builder: (context) => SafeArea(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListTile(
                            leading: Icon(page.isLocked ? Icons.lock_open : Icons.lock_outline, color: colors.inkPrimary),
                            title: Text(page.isLocked ? 'Disable Protection' : 'Enable Protection', style: TextStyle(color: colors.inkPrimary)),
                            onTap: () async {
                              Navigator.pop(context);
                              final success = await promptUnlock(context, ref, page.id);
                              if (!success) return;
                              ref.read(syncRepoProvider).updatePageLock(page.id, !page.isLocked);
                            },
                          ),
                          ListTile(
                            leading: Icon(Icons.edit, color: colors.inkPrimary),
                            title: Text('Rename', style: TextStyle(color: colors.inkPrimary)),
                            onTap: () async {
                              Navigator.pop(context);
                              final ctrl = TextEditingController(text: page.title);
                              final newTitle = await showDialog<String>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: colors.surfacePanel,
                                  title: Text('Rename Page', style: TextStyle(color: colors.inkPrimary)),
                                  content: TextField(
                                    controller: ctrl,
                                    autofocus: true,
                                    style: TextStyle(color: colors.inkPrimary),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: colors.surfaceBase,
                                      border: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: Text('Cancel', style: TextStyle(color: colors.inkMuted)),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, ctrl.text),
                                      child: Text('Rename', style: TextStyle(color: colors.accent)),
                                    ),
                                  ],
                                ),
                              );
                              if (newTitle != null && newTitle.isNotEmpty) {
                                await ref.read(syncRepoProvider).updatePageTitle(page.id, newTitle);
                              }
                            },
                          ),
                          ListTile(
                            leading: const Icon(Icons.delete, color: Color(0xFFCF6679)),
                            title: const Text('Delete', style: TextStyle(color: Color(0xFFCF6679))),
                            onTap: () async {
                              Navigator.pop(context);
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: colors.surfacePanel,
                                  title: Text('Delete Page?', style: TextStyle(color: colors.inkPrimary)),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, false),
                                      child: Text('Cancel', style: TextStyle(color: colors.inkMuted)),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(context, true),
                                      child: const Text('Delete', style: TextStyle(color: Color(0xFFCF6679))),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await ref.read(syncRepoProvider).deletePage(page.id);
                                if (ref.read(activePageProvider) == page.id) {
                                  ref.read(activePageProvider.notifier).select(null);
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Text('Error loading pages', style: TextStyle(color: colors.inkMuted)),
        ),
      ),
    );
  }
}

/// Isolated widget for the lock-reset button in the mobile AppBar.
/// Uses `.select` to only rebuild when the session set transitions
/// between empty ↔ non-empty, instead of on every mutation.
class _LockResetButton extends ConsumerWidget {
  const _LockResetButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUnlocked = ref.watch(
      unlockedSessionProvider.select((s) => s.isNotEmpty),
    );
    if (!hasUnlocked) return const SizedBox.shrink();

    final colors = AppTheme.colorsOf(context);
    return IconButton(
      icon: Icon(Icons.lock_reset, color: colors.accent),
      onPressed: () {
        ref.read(unlockedSessionProvider.notifier).clear();
      },
      tooltip: 'Lock active items',
    );
  }
}
