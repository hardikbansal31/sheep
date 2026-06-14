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

/// Linear stack navigator for mobile: Sections → Pages → Editor.
class MobileShell extends ConsumerWidget {
  const MobileShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(mobileNavIndexProvider);
    final colors = AppTheme.colorsOf(context);

    return Scaffold(
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
      body: IndexedStack(
        index: index,
        children: [
          _MobileSections(
            key: const ValueKey(0),
            onTap: () => ref.read(mobileNavIndexProvider.notifier).go(1),
          ),
          _MobilePages(
            key: const ValueKey(1),
            onTap: () => ref.read(mobileNavIndexProvider.notifier).go(2),
          ),
          SafeArea(
            key: const ValueKey(2),
            bottom: false,
            child: RepaintBoundary(
              child: EditorPane(key: editorPaneKey),
            ),
          ),
        ],
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
                leading: Icon(Icons.folder_outlined, color: colors.inkMuted, size: 20),
                title: Text(
                  section.title,
                  style: TextStyle(color: colors.inkPrimary, fontSize: 14),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: colors.inkMuted, size: 20),
                onTap: () {
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
                title: Text(
                  page.title,
                  style: TextStyle(color: colors.inkPrimary, fontSize: 14),
                ),
                subtitle: Text(
                  DateFormat('MMM d, yyyy').format(page.updatedAt),
                  style: TextStyle(color: colors.inkMuted, fontSize: 12),
                ),
                trailing: Icon(Icons.chevron_right_rounded, color: colors.inkMuted, size: 20),
                onTap: () {
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
