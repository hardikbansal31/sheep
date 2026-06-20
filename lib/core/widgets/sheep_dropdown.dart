import 'package:flutter/material.dart';
import '../../core/theme/app_theme.dart';

class SheepDropdownItem<T> {
  final T value;
  final String label;
  final Widget? icon;

  const SheepDropdownItem({
    required this.value,
    required this.label,
    this.icon,
  });
}

class SheepDropdown<T> extends StatefulWidget {
  final T value;
  final List<SheepDropdownItem<T>> items;
  final ValueChanged<T> onChanged;
  final Widget Function(BuildContext context, SheepDropdownItem<T> selectedItem)? selectedItemBuilder;
  final double dropdownWidth;
  final double maxDropdownHeight;

  const SheepDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.selectedItemBuilder,
    this.dropdownWidth = 150,
    this.maxDropdownHeight = 300,
  });

  @override
  State<SheepDropdown<T>> createState() => _SheepDropdownState<T>();
}

class _SheepDropdownState<T> extends State<SheepDropdown<T>> with SingleTickerProviderStateMixin {
  final OverlayPortalController _overlayController = OverlayPortalController();
  final LayerLink _layerLink = LayerLink();
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    final curve = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(curve);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curve);
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _toggleDropdown() {
    if (_overlayController.isShowing) {
      _closeDropdown();
    } else {
      _overlayController.show();
      _animationController.forward(from: 0);
    }
  }

  void _closeDropdown() {
    _animationController.reverse().then((_) {
      if (mounted) {
        _overlayController.hide();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final selectedItem = widget.items.firstWhere(
      (i) => i.value == widget.value,
      orElse: () => widget.items.isNotEmpty ? widget.items.first : SheepDropdownItem<T>(value: widget.value, label: ''),
    );

    return CompositedTransformTarget(
      link: _layerLink,
      child: OverlayPortal(
        controller: _overlayController,
        overlayChildBuilder: (BuildContext context) {
          return Stack(
            children: [
              // Invisible tap region to close the dropdown
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _closeDropdown,
                  child: const SizedBox.expand(),
                ),
              ),
              CompositedTransformFollower(
                link: _layerLink,
                targetAnchor: Alignment.bottomLeft,
                followerAnchor: Alignment.topLeft,
                offset: const Offset(0, 4),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: ScaleTransition(
                      scale: _scaleAnimation,
                      alignment: Alignment.topCenter,
                      child: Material(
                        color: Colors.transparent,
                        child: Container(
                          width: widget.dropdownWidth,
                          constraints: BoxConstraints(maxHeight: widget.maxDropdownHeight),
                          decoration: BoxDecoration(
                            color: colors.surfacePanel,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.border),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withAlpha(25),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: widget.items.map((item) {
                                  final isSelected = item.value == widget.value;
                                  return _DropdownItemWidget<T>(
                                    item: item,
                                    isSelected: isSelected,
                                    colors: colors,
                                    onTap: () {
                                      widget.onChanged(item.value);
                                      _closeDropdown();
                                    },
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _toggleDropdown,
            borderRadius: BorderRadius.circular(8),
            hoverColor: colors.accent.withAlpha(25),
            splashColor: colors.accent.withAlpha(25),
            highlightColor: colors.accent.withAlpha(25),
            child: widget.selectedItemBuilder != null
                ? widget.selectedItemBuilder!(context, selectedItem)
                : Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: colors.surfacePanel,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selectedItem.icon != null) ...[
                          selectedItem.icon!,
                          const SizedBox(width: 8),
                        ],
                        Text(
                          selectedItem.label,
                          style: TextStyle(color: colors.inkPrimary, fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_drop_down, color: colors.inkPrimary, size: 20),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _DropdownItemWidget<T> extends StatefulWidget {
  final SheepDropdownItem<T> item;
  final bool isSelected;
  final AppColors colors;
  final VoidCallback onTap;

  const _DropdownItemWidget({
    required this.item,
    required this.isSelected,
    required this.colors,
    required this.onTap,
  });

  @override
  State<_DropdownItemWidget<T>> createState() => _DropdownItemWidgetState<T>();
}

class _DropdownItemWidgetState<T> extends State<_DropdownItemWidget<T>> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final isSelected = widget.isSelected;
    final item = widget.item;

    return InkWell(
      onTap: widget.onTap,
      onHover: (hover) {
        if (mounted && _isHovered != hover) {
          setState(() => _isHovered = hover);
        }
      },
      hoverColor: colors.accent.withAlpha(25),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        color: isSelected ? colors.accent.withAlpha(38) : Colors.transparent,
        child: Row(
          children: [
            if (item.icon != null) ...[
              item.icon!,
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                item.label,
                style: TextStyle(
                  color: (isSelected || _isHovered) ? colors.accent : colors.inkPrimary,
                  fontSize: 14,
                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
