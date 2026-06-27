import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/sync/sync_providers.dart';
import '../../core/update/update_service.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

/// Switches between [DesktopShell] and [MobileShell] at 760px breakpoint.
class LayoutShell extends ConsumerStatefulWidget {
  const LayoutShell({super.key});

  static const double mobileBreakpoint = 760;

  @override
  ConsumerState<LayoutShell> createState() => _LayoutShellState();
}

class _LayoutShellState extends ConsumerState<LayoutShell> {
  @override
  void initState() {
    super.initState();
    // Fire‑and‑forget update check after the first frame so it never
    // blocks the initial layout/paint. Silently swallows all errors.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UpdateService.instance.checkOnStartup(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Listen for sync completion and trigger incremental FTS rebuild.
    // Only fires when status transitions TO synced (i.e. a sync batch finished).
    ref.listen<SyncStatus>(syncStatusProvider, (previous, next) {
      if (next == SyncStatus.synced && previous != SyncStatus.synced) {
        ref.read(syncRepoProvider).syncFtsIncrementally();
      }
    });

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < LayoutShell.mobileBreakpoint) {
          return const MobileShell();
        }
        return const DesktopShell();
      },
    );
  }
}
