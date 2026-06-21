import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/sync_repository.dart';
import '../sync/sync_status_dot.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../layout/providers.dart';
import '../pages/providers.dart';
import '../settings/providers.dart';
import '../settings/settings_modal.dart';
import '../settings/settings_state.dart';
import 'providers.dart';
import '../auth/desktop_pin_modal.dart';
import '../../core/auth/auth_providers.dart';

class SectionsPane extends ConsumerWidget {
  const SectionsPane({super.key});

  static const double paneWidth = 240;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final sectionsAsync = ref.watch(sectionsProvider);
    final activeSectionId = ref.watch(activeSectionProvider);

    ref.listen<AsyncValue<List<SyncSection>>>(sectionsProvider, (previous, next) {
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
    final uiScale = ref.watch(
      settingsProvider.select((s) => (s.value ?? const SettingsState()).uiScale),
    );
    final unlockedSession = ref.watch(unlockedSessionProvider);

    return Container(
      height: AppSpacing.xxl,
      padding: const EdgeInsets.only(left: AppSpacing.md, right: AppSpacing.xs),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            'Sections',
            style: TextStyle(
              color: colors.inkSecondary,
              fontSize: 11 * uiScale,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          if (unlockedSession.isNotEmpty) ...[
            IconButton(
              icon: Icon(Icons.lock_reset, color: colors.accent, size: 18),
              onPressed: () {
                ref.read(unlockedSessionProvider.notifier).clear();
              },
              splashRadius: 16,
              tooltip: 'Lock active items',
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          IconButton(
            icon: Icon(Icons.view_sidebar_outlined,
                color: colors.inkSecondary, size: 18),
            onPressed: () =>
                ref.read(sectionsPaneVisibleProvider.notifier).toggle(),
            splashRadius: 16,
            tooltip: 'Toggle sections (Ctrl+S)',
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
            icon: Icon(Icons.settings_outlined, color: colors.inkSecondary, size: 18),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const SettingsModal(),
              );
            },
            splashRadius: 16,
            tooltip: 'Settings (Ctrl+,)',
          ),
          const SizedBox(width: AppSpacing.xs),
          const SyncStatusDot(),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.add_rounded, color: colors.inkSecondary, size: 18),
            onPressed: () async {
              final section = await ref.read(syncRepoProvider).createSection('New Section');
              ref.read(activePageProvider.notifier).select(null);
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

class _SectionItem extends ConsumerStatefulWidget {
  const _SectionItem({
    required this.section,
    required this.isSelected,
    required this.onTap,
  });

  final SyncSection section;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  ConsumerState<_SectionItem> createState() => _SectionItemState();
}

class _SectionItemState extends ConsumerState<_SectionItem> {
  bool _isRenaming = false;
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.section.title);
    _focusNode = FocusNode()
      ..addListener(() {
        if (!_focusNode.hasFocus && _isRenaming) {
          _saveRename();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _saveRename() {
    if (!_isRenaming) return;
    
    final val = _controller.text.trim();
    if (val.isEmpty) {
      // Revert to old name if empty
      _controller.text = widget.section.title;
    } else if (val != widget.section.title) {
      ref.read(syncRepoProvider).updateSectionTitle(widget.section.id, val);
    }
    
    setState(() {
      _isRenaming = false;
    });
  }

  void _showDeleteConfirmationDialog(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.surfacePanel,
        title: Text('Delete Section?', style: TextStyle(color: colors.inkPrimary)),
        content: Text(
          'Delete "${widget.section.title}" and all its pages?',
          style: TextStyle(color: colors.inkPrimary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('Cancel', style: TextStyle(color: colors.inkMuted)),
          ),
          TextButton(
            onPressed: () {
              ref.read(syncRepoProvider).softDeleteSection(widget.section.id);
              if (widget.isSelected) {
                ref.read(activePageProvider.notifier).select(null);
                ref.read(activeSectionProvider.notifier).select(null);
              }
              Navigator.of(context).pop();
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final uiScale = ref.watch(
      settingsProvider.select((s) => (s.value ?? const SettingsState()).uiScale),
    );
    
    // Keep controller in sync with external title changes if not renaming
    if (!_isRenaming && _controller.text != widget.section.title) {
      _controller.text = widget.section.title;
    }
    
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 1,
      ),
      child: Material(
        color: widget.isSelected ? colors.surfaceHover : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: GestureDetector(
          onSecondaryTapDown: (details) {
            if (_isRenaming) return;
            showMenu(
              context: context,
              position: RelativeRect.fromLTRB(
                details.globalPosition.dx,
                details.globalPosition.dy,
                details.globalPosition.dx,
                details.globalPosition.dy,
              ),
              color: colors.surfacePanel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: colors.border),
              ),
              elevation: 4,
              items: [
                PopupMenuItem(
                  value: 'rename',
                  child: Text('Rename', style: TextStyle(color: colors.inkPrimary, fontSize: 14 * uiScale)),
                ),
                PopupMenuItem(
                  value: 'lock_toggle',
                  child: Text(widget.section.isLocked ? 'Disable Protection' : 'Enable Protection', style: TextStyle(color: colors.inkPrimary, fontSize: 14 * uiScale)),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete', style: TextStyle(color: Colors.red, fontSize: 14 * uiScale)),
                ),
              ],
            ).then((value) async {
              if (!context.mounted) return;
              if (value == 'rename') {
                setState(() {
                  _isRenaming = true;
                });
                _focusNode.requestFocus();
              } else if (value == 'lock_toggle') {
                final success = await promptUnlock(context, ref, widget.section.id);
                if (!success) return;

                ref.read(syncRepoProvider).updateSectionLock(widget.section.id, !widget.section.isLocked);
              } else if (value == 'delete') {
                _showDeleteConfirmationDialog(context);
              }
            });
          },
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            hoverColor: colors.surfaceHover,
            onTap: () async {
              if (_isRenaming) return;
              
              if (widget.section.isLocked) {
                final session = ref.read(unlockedSessionProvider);
                if (!session.contains(widget.section.id)) {
                  final unlocked = await promptUnlock(context, ref, widget.section.id);
                  if (!unlocked) return;
                }
              }

              ref.read(activePageProvider.notifier).select(null);
              widget.onTap();
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Icon(
                    widget.section.isLocked ? Icons.lock_outline : Icons.folder_outlined,
                    color: widget.isSelected ? colors.accent : colors.inkSecondary,
                    size: 16 * uiScale,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: _isRenaming
                        ? TextField(
                            controller: _controller,
                            focusNode: _focusNode,
                            style: TextStyle(
                              color: widget.isSelected ? colors.accent : colors.inkPrimary,
                              fontSize: 13 * uiScale,
                              fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              border: InputBorder.none,
                            ),
                            onSubmitted: (_) => _saveRename(),
                          )
                        : Text(
                            widget.section.title,
                            style: TextStyle(
                              color: widget.isSelected ? colors.accent : colors.inkPrimary,
                              fontSize: 13 * uiScale,
                              fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
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


