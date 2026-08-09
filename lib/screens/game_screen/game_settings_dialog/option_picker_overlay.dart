import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';

/// A generic gamepad-navigable option picker overlay.
///
/// Mirrors the language picker in general settings. Pops with the chosen
/// [OptionPickerItem.value], or null when dismissed.
class OptionPickerItem {
  final String value;
  final String label;

  const OptionPickerItem({required this.value, required this.label});
}

class OptionPickerOverlay extends StatefulWidget {
  final Offset anchorOffset;
  final String currentValue;
  final List<OptionPickerItem> options;

  const OptionPickerOverlay({
    super.key,
    required this.anchorOffset,
    required this.currentValue,
    required this.options,
  });

  @override
  State<OptionPickerOverlay> createState() => OptionPickerOverlayState();
}

class OptionPickerOverlayState extends State<OptionPickerOverlay> {
  late GamepadNavigation _gamepadNav;
  int _selectedIndex = 0;

  final List<GlobalKey> _itemKeys = [];
  final GlobalKey _colKey = GlobalKey();
  double _indicatorTop = -1;

  @override
  void initState() {
    super.initState();
    _itemKeys.addAll(List.generate(widget.options.length, (_) => GlobalKey()));

    _selectedIndex = widget.options.indexWhere(
      (o) => o.value == widget.currentValue,
    );
    if (_selectedIndex < 0) _selectedIndex = 0;

    _gamepadNav = GamepadNavigation(
      onNavigateUp: () {
        setState(() {
          _selectedIndex =
              (_selectedIndex - 1 + widget.options.length) %
              widget.options.length;
        });
        _updateIndicator();
        SfxService().playNavSound();
      },
      onNavigateDown: () {
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % widget.options.length;
        });
        _updateIndicator();
        SfxService().playNavSound();
      },
      onSelectItem: _handleSelection,
      onBack: () => Navigator.pop(context),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'option_picker_overlay',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
      _updateIndicator();
    });
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('option_picker_overlay');
    _gamepadNav.dispose();
    super.dispose();
  }

  /// Calculates the visual position of the selection indicator.
  void _updateIndicator() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _itemKeys[_selectedIndex];
      final RenderBox? box =
          key.currentContext?.findRenderObject() as RenderBox?;
      final RenderBox? colBox =
          _colKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && colBox != null) {
        final pos = box.localToGlobal(Offset.zero, ancestor: colBox);
        setState(() => _indicatorTop = pos.dy);
      }
    });
  }

  void _handleSelection() {
    SfxService().playEnterSound();
    Navigator.pop(context, widget.options[_selectedIndex].value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screenSize = MediaQuery.of(context).size;
    final overlayWidth = 180.r;
    final itemHeight = 24;
    final overlayHeight = itemHeight * widget.options.length + 16;

    // Anchor: right-aligned relative to the trigger row, clamped to viewport.
    double left = widget.anchorOffset.dx - overlayWidth;
    double top = widget.anchorOffset.dy - overlayHeight.r / 1.5;
    left = left.clamp(8.0, screenSize.width - overlayWidth - 8);
    top = top.clamp(8.0, screenSize.height - overlayHeight - 8);

    return Stack(
      children: [
        Positioned(
          left: left,
          top: top,
          width: overlayWidth,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 8.r),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 15,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Stack(
                key: _colKey,
                children: [
                  if (_indicatorTop >= 0)
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 150),
                      curve: Curves.easeInOut,
                      top: _indicatorTop,
                      left: 6.r,
                      right: 4.r,
                      height: itemHeight.r,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.15,
                          ),
                          borderRadius: BorderRadius.circular(8.r),
                          border: Border.all(
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.3,
                            ),
                            width: 0.5.r,
                          ),
                        ),
                      ),
                    ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widget.options.asMap().entries.map((entry) {
                      final i = entry.key;
                      final option = entry.value;
                      final isSelected = option.value == widget.currentValue;
                      return SizedBox(
                        key: _itemKeys[i],
                        height: itemHeight.r,
                        child: InkWell(
                          onTap: () {
                            setState(() => _selectedIndex = i);
                            _handleSelection();
                          },
                          onHover: (v) {
                            if (v) {
                              setState(() => _selectedIndex = i);
                              _updateIndicator();
                            }
                          },
                          focusColor: Colors.transparent,
                          hoverColor: Colors.transparent,
                          splashColor: Colors.transparent,
                          highlightColor: Colors.transparent,
                          borderRadius: BorderRadius.circular(8.r),
                          child: Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12.r),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    option.label,
                                    style: TextStyle(
                                      fontSize: 10.r,
                                      color: isSelected
                                          ? theme.colorScheme.primary
                                          : theme.colorScheme.onSurface,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Symbols.check_circle_rounded,
                                    size: 14.r,
                                    color: theme.colorScheme.primary,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
