import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'package:neostation/themes/corner_radii.dart';

class HeaderActionButton extends StatelessWidget {
  /// Optional leading glyph. Omitted by the header's own actions, which are
  /// reached with the D-pad rather than a dedicated button.
  final Widget? icon;

  final String label;
  final VoidCallback onTap;
  final Color backgroundColor;
  final Color foregroundColor;

  /// Draws the gamepad cursor on this chip.
  final bool isFocused;

  const HeaderActionButton({
    super.key,
    this.icon,
    required this.label,
    required this.onTap,
    required this.backgroundColor,
    required this.foregroundColor,
    this.isFocused = false,
  });

  @override
  Widget build(BuildContext context) {
    final radii = Theme.of(context).extension<CornerRadii>() ?? CornerRadii.m();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isFocused ? scheme.secondary : backgroundColor,
      borderRadius: radii.radiusInternal,
      child: InkWell(
        onTap: onTap,
        borderRadius: radii.radiusInternal,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radii.radiusInternal,
            border: Border.all(
              color: isFocused ? scheme.secondary : Colors.transparent,
              width: 2.r,
            ),
          ),
          padding: EdgeInsets.symmetric(horizontal: 6.r, vertical: 3.r),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[?icon, SizedBox(width: 4.r)],
              Text(
                label,
                style: TextStyle(
                  color: isFocused ? scheme.onSecondary : foregroundColor,
                  fontSize: 8.r,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
