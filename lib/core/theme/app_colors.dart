import 'package:flutter/material.dart';

/// All color tokens for the Sheep design system.
///
/// Never use hardcoded color values in widget code — always reference
/// these via [AppColors.dark] or [AppColors.light].
class AppColors {
  const AppColors._({
    required this.surfaceBase,
    required this.surfacePanel,
    required this.surfaceHover,
    required this.inkPrimary,
    required this.inkSecondary,
    required this.inkMuted,
    required this.border,
    required this.accent,
  });

  final Color surfaceBase;
  final Color surfacePanel;
  final Color surfaceHover;
  final Color inkPrimary;
  final Color inkSecondary;
  final Color inkMuted;
  final Color border;
  final Color accent;

  /// Dark theme (default) — matched to color-picker sampled values.
  static const dark = AppColors._(
    surfaceBase: Color(0xFF151515), // editor/content background — sampled
    surfacePanel: Color(0xFF20201F), // sidebar — updated sample
    surfaceHover: Color(
      0xFF2A2A29,
    ), // one step lighter than panel, for hover/active states
    inkPrimary: Color(0xFFF0EFEC), // near-white, neutral
    inkSecondary: Color(0xFF8C8C8C), // muted gray for secondary text/labels
    inkMuted: Color(0xFF5A5A5A), // placeholder/disabled text
    border: Color(0xFF2A2A29), // matches surfaceHover for consistency
    accent: Color(0xFFE8652A),
  );

  /// Light theme — neutral gray family, matching the dark theme's tonal approach.
  static const light = AppColors._(
    surfaceBase: Color(0xFFFAFAFA), // main content background
    surfacePanel: Color(0xFFF0F0EF), // sidebar — slightly darker than base
    surfaceHover: Color(
      0xFFE6E6E4,
    ), // one step darker than panel, for hover/active states
    inkPrimary: Color(
      0xFF1C1C1C,
    ), // near-black, mirrors dark theme's surfaceBase
    inkSecondary: Color(0xFF6B6B6B), // muted gray for secondary text/labels
    inkMuted: Color(0xFFA3A3A1), // placeholder/disabled text
    border: Color(0xFFE6E6E4), // matches surfaceHover for consistency
    accent: Color(0xFFE8652A),
  );

  /// OLED theme — true black base for power savings / max contrast.
  /// Panels stay a hair off-black so pane edges are still legible.
  static const oled = AppColors._(
    surfaceBase: Color(0xFF000000), // true black
    surfacePanel: Color(
      0xFF0E0E0D,
    ), // sidebar — same proportional step as dark theme
    surfaceHover: Color(0xFF181817), // one step lighter than panel
    inkPrimary: Color(0xFFEDEDED), // matches dark theme
    inkSecondary: Color(0xFF8C8C8C), // matches dark theme
    inkMuted: Color(0xFF5A5A5A), // matches dark theme
    border: Color(0xFF181817), // matches surfaceHover for consistency
    accent: Color(0xFFE8652A),
  );
}
