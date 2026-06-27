import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/update/update_service.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

/// Switches between [DesktopShell] and [MobileShell] at 760px breakpoint.
class LayoutShell extends StatefulWidget {
  const LayoutShell({super.key});

  static const double mobileBreakpoint = 760;

  @override
  State<LayoutShell> createState() => _LayoutShellState();
}

class _LayoutShellState extends State<LayoutShell> {
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
