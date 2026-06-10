import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

export 'app_colors.dart';
export 'app_spacing.dart';

/// Provides [ThemeData] for both dark and light modes, built entirely
/// from [AppColors] tokens.  Access the current palette in widget code via
/// [AppTheme.colorsOf(context)].
abstract final class AppTheme {
  // ─── public API ───────────────────────────────────────────────

  static ThemeData get dark => _build(AppColors.dark, Brightness.dark);
  static ThemeData get light => _build(AppColors.light, Brightness.light);

  /// Retrieve the [AppColors] palette from the nearest [Theme].
  ///
  /// Usage:  `final c = AppTheme.colorsOf(context);`
  static AppColors colorsOf(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return brightness == Brightness.dark ? AppColors.dark : AppColors.light;
  }

  // ─── internals ────────────────────────────────────────────────

  static ThemeData _build(AppColors c, Brightness brightness) {
    final baseText = GoogleFonts.interTextTheme(
      brightness == Brightness.dark
          ? ThemeData.dark().textTheme
          : ThemeData.light().textTheme,
    );

    final textTheme = baseText.apply(
      bodyColor: c.inkPrimary,
      displayColor: c.inkPrimary,
    );

    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: c.surfaceBase,
      canvasColor: c.surfacePanel,
      cardColor: c.surfacePanel,
      dividerColor: c.border,
      textTheme: textTheme,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: c.accent,
        onPrimary: Colors.white,
        secondary: c.inkSecondary,
        onSecondary: c.inkPrimary,
        surface: c.surfaceBase,
        onSurface: c.inkPrimary,
        error: const Color(0xFFCF6679),
        onError: Colors.black,
        surfaceContainerHighest: c.surfacePanel,
        outline: c.border,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.surfacePanel,
        foregroundColor: c.inkPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      iconTheme: IconThemeData(color: c.inkSecondary, size: 20),
      dividerTheme: DividerThemeData(color: c.border, thickness: 1, space: 0),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(c.inkMuted.withValues(alpha: 0.4)),
        radius: const Radius.circular(4),
        thickness: WidgetStateProperty.all(4),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: c.surfaceHover,
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: TextStyle(color: c.inkPrimary, fontSize: 12),
      ),
    );
  }
}
