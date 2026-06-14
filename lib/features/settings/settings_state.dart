import 'package:flutter/material.dart';

class SettingsState {
  const SettingsState({
    this.themeMode = ThemeMode.system,
    this.fontTitle = 'Playfair Display',
    this.fontHeadings = 'Merriweather',
    this.fontParagraph = 'Inter',
    this.fontCode = 'JetBrains Mono',
    this.defaultFontSize = 16.0,
  });

  final ThemeMode themeMode;
  final String fontTitle;
  final String fontHeadings;
  final String fontParagraph;
  final String fontCode;
  final double defaultFontSize;

  SettingsState copyWith({
    ThemeMode? themeMode,
    String? fontTitle,
    String? fontHeadings,
    String? fontParagraph,
    String? fontCode,
    double? defaultFontSize,
  }) {
    return SettingsState(
      themeMode: themeMode ?? this.themeMode,
      fontTitle: fontTitle ?? this.fontTitle,
      fontHeadings: fontHeadings ?? this.fontHeadings,
      fontParagraph: fontParagraph ?? this.fontParagraph,
      fontCode: fontCode ?? this.fontCode,
      defaultFontSize: defaultFontSize ?? this.defaultFontSize,
    );
  }
}

extension UiScale on SettingsState {
  double get uiScale => (defaultFontSize / 14.0).clamp(0.8, 1.25);
}
