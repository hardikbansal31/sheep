import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/update/update_service.dart';
import '../../core/widgets/sheep_dropdown.dart';
import 'providers.dart';
import 'settings_state.dart';

class SettingsModal extends ConsumerWidget {
  const SettingsModal({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final settingsAsync = ref.watch(settingsProvider);

    final isMobileWidth = MediaQuery.of(context).size.width < 760;

    if (isMobileWidth) {
      return Dialog.fullscreen(
        backgroundColor: colors.surfaceBase,
        child: SafeArea(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
            child: settingsAsync.when(
              data: (settings) => _SettingsContent(settings: settings, isMobileWidth: true),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('Error loading settings', style: TextStyle(color: colors.inkPrimary))),
            ),
          ),
        ),
      );
    }

    return Dialog(
      backgroundColor: colors.surfaceBase,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 480,
        constraints: const BoxConstraints(maxHeight: 600),
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: settingsAsync.when(
          data: (settings) => _SettingsContent(settings: settings, isMobileWidth: false),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error loading settings', style: TextStyle(color: colors.inkPrimary))),
        ),
      ),
    );
  }
}

class _SettingsContent extends ConsumerStatefulWidget {
  const _SettingsContent({required this.settings, required this.isMobileWidth});

  final SettingsState settings;
  final bool isMobileWidth;

  @override
  ConsumerState<_SettingsContent> createState() => _SettingsContentState();
}

class _SettingsContentState extends ConsumerState<_SettingsContent> {
  bool _isCheckingUpdate = false;
  String? _updateMessage;

  Future<void> _checkForUpdates() async {
    setState(() {
      _isCheckingUpdate = true;
      _updateMessage = null;
    });

    final result = await UpdateService.instance.checkManually(context);

    if (!mounted) return;
    setState(() {
      _isCheckingUpdate = false;
      _updateMessage = result.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final settings = widget.settings;
    final uiScale = settings.uiScale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: widget.isMobileWidth ? MainAxisSize.max : MainAxisSize.min,
      children: [
        Row(
          children: [
            if (widget.isMobileWidth) ...[
              IconButton(
                icon: Icon(Icons.arrow_back, color: colors.inkPrimary),
                onPressed: () => Navigator.of(context).pop(),
                splashRadius: 24,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: AppSpacing.md),
            ],
            Text(
              'Settings',
              style: TextStyle(
                color: colors.inkPrimary,
                fontSize: 20 * uiScale,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
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
                  child: SheepDropdown<ThemeMode>(
                    value: settings.themeMode,
                    dropdownWidth: 100,
                    alignRight: true,
                    items: const [
                      SheepDropdownItem(value: ThemeMode.system, label: 'System'),
                      SheepDropdownItem(value: ThemeMode.light, label: 'Light'),
                      SheepDropdownItem(value: ThemeMode.dark, label: 'Dark'),
                    ],
                    onChanged: (val) => ref.read(settingsProvider.notifier).setThemeMode(val),
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
                  child: SheepDropdown<double>(
                    value: settings.defaultFontSize,
                    dropdownWidth: 100,
                    alignRight: true,
                    items: [10.0, 11.0, 12.0, 13.0, 14.0, 16.0, 18.0, 20.0, 24.0, 28.0, 32.0, 36.0, 48.0]
                        .map((size) => SheepDropdownItem(value: size, label: '${size.toInt()}pt'))
                        .toList(),
                    onChanged: (val) => ref.read(settingsProvider.notifier).setDefaultFontSize(val),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _SectionTitle(title: 'Updates', colors: colors, uiScale: uiScale),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'App Updates',
                              style: TextStyle(color: colors.inkPrimary, fontSize: 14 * uiScale),
                            ),
                            if (_updateMessage != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _updateMessage!,
                                style: TextStyle(color: colors.inkSecondary, fontSize: 12 * uiScale),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 36,
                        child: _isCheckingUpdate
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.accent,
                                ),
                              )
                            : TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: colors.accent,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(color: colors.border),
                                  ),
                                ),
                                onPressed: _checkForUpdates,
                                child: Text(
                                  'Check for Updates',
                                  style: TextStyle(fontSize: 13 * uiScale),
                                ),
                              ),
                      ),
                    ],
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
      child: SheepDropdown<String>(
        value: safeValue,
        dropdownWidth: 160,
        alignRight: true,
        items: _fontOptions
            .map((font) => SheepDropdownItem(value: font, label: font))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }
}
