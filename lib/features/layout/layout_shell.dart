import 'package:flutter/material.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

/// Switches between [DesktopShell] and [MobileShell] at 760px breakpoint.
class LayoutShell extends StatelessWidget {
  const LayoutShell({super.key});

  static const double mobileBreakpoint = 760;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < mobileBreakpoint) {
          return const MobileShell();
        }
        return const DesktopShell();
      },
    );
  }
}
