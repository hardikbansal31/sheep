import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'settings_state.dart';

class SettingsNotifier extends AsyncNotifier<SettingsState> {
  @override
  Future<SettingsState> build() async {
    final repo = ref.watch(repositoryProvider);
    
    final themeStr = await repo.getPreference('theme') ?? 'system';
    final ThemeMode themeMode = _parseThemeMode(themeStr);
    
    final fontTitle = await repo.getPreference('font_title') ?? 'Merriweather';
    final fontHeadings = await repo.getPreference('font_headings') ?? 'Inter';
    final fontParagraph = await repo.getPreference('font_paragraph') ?? 'Inter';
    final fontCode = await repo.getPreference('font_code') ?? 'JetBrains Mono';
    
    final fontSizeStr = await repo.getPreference('font_size_default') ?? '14.0';
    final defaultFontSize = double.tryParse(fontSizeStr) ?? 14.0;

    return SettingsState(
      themeMode: themeMode,
      fontTitle: fontTitle,
      fontHeadings: fontHeadings,
      fontParagraph: fontParagraph,
      fontCode: fontCode,
      defaultFontSize: defaultFontSize,
    );
  }

  ThemeMode _parseThemeMode(String val) {
    switch (val) {
      case 'light': return ThemeMode.light;
      case 'dark': return ThemeMode.dark;
      default: return ThemeMode.system;
    }
  }

  String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light: return 'light';
      case ThemeMode.dark: return 'dark';
      default: return 'system';
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final repo = ref.read(repositoryProvider);
    await repo.setPreference('theme', _themeModeToString(mode));
    if (state.hasValue) {
      state = AsyncData(state.value!.copyWith(themeMode: mode));
    }
  }

  Future<void> setFontTitle(String font) async {
    final repo = ref.read(repositoryProvider);
    await repo.setPreference('font_title', font);
    if (state.hasValue) {
      state = AsyncData(state.value!.copyWith(fontTitle: font));
    }
  }

  Future<void> setFontHeadings(String font) async {
    final repo = ref.read(repositoryProvider);
    await repo.setPreference('font_headings', font);
    if (state.hasValue) {
      state = AsyncData(state.value!.copyWith(fontHeadings: font));
    }
  }

  Future<void> setFontParagraph(String font) async {
    final repo = ref.read(repositoryProvider);
    await repo.setPreference('font_paragraph', font);
    if (state.hasValue) {
      state = AsyncData(state.value!.copyWith(fontParagraph: font));
    }
  }

  Future<void> setFontCode(String font) async {
    final repo = ref.read(repositoryProvider);
    await repo.setPreference('font_code', font);
    if (state.hasValue) {
      state = AsyncData(state.value!.copyWith(fontCode: font));
    }
  }

  Future<void> setDefaultFontSize(double size) async {
    final repo = ref.read(repositoryProvider);
    await repo.setPreference('font_size_default', size.toString());
    if (state.hasValue) {
      state = AsyncData(state.value!.copyWith(defaultFontSize: size));
    }
  }
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, SettingsState>(() {
  return SettingsNotifier();
});
