import 'package:animated_toggle_switch/animated_toggle_switch.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/services/sfx_service.dart';

class CustomToggleSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final bool disabled;

  const CustomToggleSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.disabled = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final effectiveActiveColor = activeColor ?? scheme.primary;

    // The full-saturation daisyUI primaries read as a gaudy slab when they
    // flood the whole pill. Keep the accent on the moving indicator (thumb)
    // and give the ON track only a soft tonal tint of that colour, layered
    // over the surface — closer to how daisyUI uses primary as an accent.
    final activeTrackColor = Color.alphaBlend(
      effectiveActiveColor.withValues(alpha: 0.20),
      scheme.surface,
    );

    // Colour sitting on top of the active (primary) indicator.
    final onActiveIndicator = effectiveActiveColor == scheme.secondary
        ? scheme.onSecondary
        : scheme.onPrimary;

    final toggle = AnimatedToggleSwitch<bool>.dual(
      indicatorSize: Size(24.r, 24.r),
      current: value,
      first: false,
      second: true,
      spacing: 16.r,
      height: 28.r,
      style: ToggleStyle(borderColor: Colors.transparent),
      borderWidth: 2.r,
      onChanged: disabled
          ? null
          : (T) {
              if (T) {
                SfxService().playEnterSound();
              } else {
                SfxService().playBackSound();
              }
              onChanged?.call(T);
            },
      styleBuilder: (b) => ToggleStyle(
        backgroundColor: b ? activeTrackColor : scheme.surface,
        indicatorColor: b ? effectiveActiveColor : scheme.onSurfaceVariant,
      ),
      iconBuilder: (value) => Icon(
        value ? Symbols.check_rounded : Symbols.close_rounded,
        size: 12.r,
        // Icon rides the indicator: contrast against the primary thumb when
        // ON, against the neutral thumb when OFF.
        color: value ? onActiveIndicator : scheme.surface,
      ),
      textBuilder: (value) => Center(
        child: Text(
          value ? 'ON' : 'OFF',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 8.r,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );

    if (disabled) {
      return IgnorePointer(child: Opacity(opacity: 0.6, child: toggle));
    }

    return toggle;
  }
}
