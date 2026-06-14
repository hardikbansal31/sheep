import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import 'providers.dart';
import 'settings_state.dart';

class SettingsModal extends ConsumerWidget {
  const SettingsModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final settingsAsync = ref.watch(settingsProvider);

    return Dialog(
      backgroundColor: colors.surfaceBase,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: settingsAsync.when(
          data: (settings) => _SettingsContent(settings: settings),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error loading settings', style: TextStyle(color: colors.inkPrimary))),
        ),
      ),
    );
  }
}

class _SettingsContent extends ConsumerWidget {
  const _SettingsContent({required this.settings});

  final SettingsState settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final uiScale = settings.uiScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Settings',
          style: TextStyle(
            color: colors.inkPrimary,
            fontSize: 20 * uiScale,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionTitle(title: 'Appearance', colors: colors, uiScale: uiScale),
                _SettingRow(
                  label: 'Theme',
                  colors: colors,
                  uiScale: uiScale,
                  child: DropdownButton<ThemeMode>(
                    value: settings.themeMode,
                    icon: Icon(Icons.arrow_drop_down, color: colors.inkMuted),
                    dropdownColor: colors.surfacePanel,
                    style: TextStyle(color: colors.inkPrimary, fontSize: 14),
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                      DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                      DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(settingsProvider.notifier).setThemeMode(val);
                      }
                    },
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _SectionTitle(title: 'Typography', colors: colors, uiScale: uiScale),
                _FontDropdownRow(
                  label: 'Title Font',
                  value: settings.fontTitle,
                  colors: colors,
                  uiScale: uiScale,
                  onChanged: (val) => ref.read(settingsProvider.notifier).setFontTitle(val),
                ),
                _FontDropdownRow(
                  label: 'Headings Font',
                  value: settings.fontHeadings,
                  colors: colors,
                  uiScale: uiScale,
                  onChanged: (val) => ref.read(settingsProvider.notifier).setFontHeadings(val),
                ),
                _FontDropdownRow(
                  label: 'Paragraph Font',
                  value: settings.fontParagraph,
                  colors: colors,
                  uiScale: uiScale,
                  onChanged: (val) => ref.read(settingsProvider.notifier).setFontParagraph(val),
                ),
                _FontDropdownRow(
                  label: 'Code Font',
                  value: settings.fontCode,
                  colors: colors,
                  uiScale: uiScale,
                  onChanged: (val) => ref.read(settingsProvider.notifier).setFontCode(val),
                ),
                _SettingRow(
                  label: 'Default Font Size',
                  colors: colors,
                  uiScale: uiScale,
                  child: DropdownButton<double>(
                    value: settings.defaultFontSize,
                    icon: Icon(Icons.arrow_drop_down, color: colors.inkMuted),
                    dropdownColor: colors.surfacePanel,
                    style: TextStyle(color: colors.inkPrimary, fontSize: 14 * uiScale),
                    underline: const SizedBox(),
                    items: [10.0, 11.0, 12.0, 13.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0, 36.0, 48.0]
                        .map((size) => DropdownMenuItem(value: size, child: Text('${size.toInt()}pt')))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        ref.read(settingsProvider.notifier).setDefaultFontSize(val);
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.colors, required this.uiScale});
  final String title;
  final AppColors colors;
  final double uiScale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: colors.inkSecondary,
          fontSize: 11 * uiScale,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.child,
    required this.colors,
    required this.uiScale,
  });

  final String label;
  final Widget child;
  final AppColors colors;
  final double uiScale;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: colors.inkPrimary, fontSize: 14 * uiScale)),
          child,
        ],
      ),
    );
  }
}

class _FontDropdownRow extends StatelessWidget {
  const _FontDropdownRow({
    required this.label,
    required this.value,
    required this.colors,
    required this.uiScale,
    required this.onChanged,
  });

  final String label;
  final String value;
  final AppColors colors;
  final double uiScale;
  final ValueChanged<String> onChanged;

  static const _fontOptions = [
    'Inter',
    'Merriweather',
    'JetBrains Mono',
    'Roboto',
    'Open Sans',
    'Lato',
    'Poppins',
    'Montserrat',
    'Playfair Display',
    'Source Code Pro',
  ];

  @override
  Widget build(BuildContext context) {
    // If somehow a font is in DB but not in the list, fallback to Inter so it doesn't crash
    final safeValue = _fontOptions.contains(value) ? value : 'Inter';

    return _SettingRow(
      label: label,
      colors: colors,
      uiScale: uiScale,
      child: DropdownButton<String>(
        value: safeValue,
        icon: Icon(Icons.arrow_drop_down, color: colors.inkMuted),
        dropdownColor: colors.surfacePanel,
        style: TextStyle(color: colors.inkPrimary, fontSize: 14 * uiScale),
        underline: const SizedBox(),
        items: _fontOptions
            .map((font) => DropdownMenuItem(value: font, child: Text(font)))
            .toList(),
        onChanged: (val) {
          if (val != null) {
            onChanged(val);
          }
        },
      ),
    );
  }
}
