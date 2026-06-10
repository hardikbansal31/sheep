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

  /// Dark theme (default).
  static const dark = AppColors._(
    surfaceBase: Color(0xFF1E1E1C),
    surfacePanel: Color(0xFF252523),
    surfaceHover: Color(0xFF2E2E2B),
    inkPrimary: Color(0xFFF0EDE8),
    inkSecondary: Color(0xFF8A8680),
    inkMuted: Color(0xFF565350),
    border: Color(0xFF2E2E2B),
    accent: Color(0xFFE8652A),
  );

  /// Light theme.
  static const light = AppColors._(
    surfaceBase: Color(0xFFF9F8F5),
    surfacePanel: Color(0xFFF0EDE8),
    surfaceHover: Color(0xFFE8E4DE),
    inkPrimary: Color(0xFF1C1C1A),
    inkSecondary: Color(0xFF6B6860),
    inkMuted: Color(0xFFA8A49E),
    border: Color(0xFFE2DDD7),
    accent: Color(0xFFCC5500),
  );
}
