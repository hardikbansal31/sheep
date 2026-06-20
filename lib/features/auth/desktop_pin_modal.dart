import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/auth/auth_providers.dart';
import '../../core/theme/app_theme.dart';
import '../settings/providers.dart';
import '../settings/settings_state.dart';

Future<bool> promptUnlock(BuildContext context, WidgetRef ref, String itemId) async {
  final lockService = ref.read(lockServiceProvider);
  final session = ref.read(unlockedSessionProvider);
  if (session.contains(itemId)) return true;

  if (lockService.isMobile) {
    final success = await lockService.authenticateMobile();
    if (success) {
      lockService.unlockItem(itemId);
      return true;
    }
    return false;
  } else {
    final success = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => DesktopPinModal(itemId: itemId),
    );
    return success ?? false;
  }
}

class DesktopPinModal extends ConsumerStatefulWidget {
  const DesktopPinModal({super.key, required this.itemId});
  final String itemId;

  @override
  ConsumerState<DesktopPinModal> createState() => _DesktopPinModalState();
}

class _DesktopPinModalState extends ConsumerState<DesktopPinModal> {
  final TextEditingController _pinController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  bool _isSetup = false;
  bool _loading = true;
  bool _error = false;
  String _errorMsg = 'Incorrect PIN';
  String _setupFirstPin = '';

  @override
  void initState() {
    super.initState();
    _checkSetup();
  }

  Future<void> _checkSetup() async {
    final lockService = ref.read(lockServiceProvider);
    final isSetup = await lockService.isDesktopPinSetup();
    if (mounted) {
      setState(() {
        _isSetup = isSetup;
        _loading = false;
      });
      _focusNode.requestFocus();
    }
  }

  @override
  void dispose() {
    _pinController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submitPin(String pin) async {
    if (pin.length < 4) return;
    final lockService = ref.read(lockServiceProvider);

    if (!_isSetup) {
      if (_setupFirstPin.isEmpty) {
        setState(() {
          _setupFirstPin = pin;
          _pinController.clear();
        });
        _focusNode.requestFocus();
      } else {
        if (pin == _setupFirstPin) {
          await lockService.setupDesktopPin(pin);
          lockService.unlockItem(widget.itemId);
          if (mounted) Navigator.of(context).pop(true);
        } else {
          setState(() {
            _error = true;
            _errorMsg = 'PINs do not match';
            _setupFirstPin = '';
            _pinController.clear();
          });
          _focusNode.requestFocus();
        }
      }
    } else {
      final success = await lockService.authenticateDesktop(pin);
      if (success) {
        lockService.unlockItem(widget.itemId);
        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() {
          _error = true;
          _errorMsg = 'Incorrect PIN';
          _pinController.clear();
        });
        _focusNode.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final uiScale = ref.watch(settingsProvider.select((s) => s.value?.uiScale ?? 1.0));

    if (_loading) {
      return Dialog(
        backgroundColor: colors.surfacePanel,
        child: const Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    String title = _isSetup ? 'Enter PIN' : 'Setup PIN';
    String subtitle = _isSetup
        ? 'Unlock this note'
        : (_setupFirstPin.isEmpty ? 'Create a new PIN' : 'Confirm your PIN');

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(color: colors.inkPrimary, fontSize: 18 * uiScale, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          style: TextStyle(color: colors.inkSecondary, fontSize: 13 * uiScale),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _pinController,
          focusNode: _focusNode,
          obscureText: true,
          autofocus: true,
          maxLength: 6,
          keyboardType: TextInputType.number,
          style: TextStyle(color: colors.inkPrimary, fontSize: 24 * uiScale, letterSpacing: 8),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: '',
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
            focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.accent)),
            errorText: _error ? _errorMsg : null,
          ),
          onChanged: (val) {
            if (_error) setState(() => _error = false);
            if (val.length == 6) {
              _submitPin(val);
            }
          },
          onSubmitted: _submitPin,
        ).animate(target: _error ? 1 : 0).shake(hz: 8, curve: Curves.easeInOutCubic),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel', style: TextStyle(color: colors.inkPrimary)),
            ),
          ],
        )
      ],
    );

    return Dialog(
      backgroundColor: colors.surfacePanel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SizedBox(width: 300, child: content),
      ),
    );
  }
}
