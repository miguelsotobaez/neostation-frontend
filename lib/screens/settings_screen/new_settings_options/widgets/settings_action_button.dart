import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Circular icon button used as the trailing control on actionable settings
/// card rows (add ROM folder, rescan, edit, ES-DE import, etc.).
///
/// Brightens while its owning row is selected and switches to the theme's
/// error colour for destructive actions (remove folder, reset import).
class SettingsActionButton extends StatelessWidget {
  /// Glyph shown inside the button.
  final IconData icon;

  /// Whether the owning row currently holds gamepad focus.
  final bool selected;

  /// Renders in the error colour instead of primary for destructive actions.
  final bool isDestructive;

  const SettingsActionButton({
    super.key,
    required this.icon,
    required this.selected,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isDestructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return Container(
      padding: EdgeInsets.all(4.r),
      decoration: BoxDecoration(
        color: color.withValues(alpha: selected ? 1.0 : 0.8),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.3),
            blurRadius: 4.r,
            offset: Offset(0, 2.r),
          ),
        ],
      ),
      child: Icon(icon, color: theme.colorScheme.onPrimary, size: 16.r),
    );
  }
}
