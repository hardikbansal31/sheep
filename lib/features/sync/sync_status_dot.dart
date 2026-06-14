import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/sync/sync_providers.dart';
import '../../core/theme/app_theme.dart';

/// A small dot indicator showing the current sync status.
///
/// - Pulsing accent dot = actively syncing
/// - Static green dot = synced and connected
/// - Grey dot = offline
/// - Red dot = sync error
class SyncStatusDot extends ConsumerWidget {
  const SyncStatusDot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = AppTheme.colorsOf(context);
    final status = ref.watch(syncStatusProvider);

    Color dotColor = colors.inkMuted;
    String tooltipText = 'Offline';
    bool pulsing = false;

    switch (status) {
      case SyncStatus.syncing:
        dotColor = colors.accent;
        tooltipText = 'Syncing…';
        pulsing = true;
        break;
      case SyncStatus.synced:
        dotColor = const Color(0xFF4CAF50);
        tooltipText = 'Synced';
        pulsing = false;
        break;
      case SyncStatus.offline:
        dotColor = colors.inkMuted;
        tooltipText = 'Offline';
        pulsing = false;
        break;
      case SyncStatus.error:
        dotColor = const Color(0xFFCF6679);
        tooltipText = 'Sync error';
        pulsing = false;
        break;
    }

    return Tooltip(
      message: tooltipText,
      child: pulsing
          ? _PulsingDot(color: dotColor)
          : Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dotColor,
              ),
            ),
    );
  }
}

class _PulsingDot extends StatefulWidget {
  const _PulsingDot({required this.color});
  final Color color;

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Opacity(
          opacity: 0.4 + (_controller.value * 0.6),
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        );
      },
    );
  }
}
