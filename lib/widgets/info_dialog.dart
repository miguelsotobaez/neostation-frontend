import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/utils/gamepad_nav.dart';

/// Simple gamepad-friendly information dialog with a single OK button.
///
/// Mirrors [ConfirmActionDialog]'s gamepad wiring: the navigation layer is
/// registered after the first frame and activation is delegated to
/// [GamepadNavigationManager]. A or B dismisses the dialog.
class InfoDialog extends StatefulWidget {
  final String title;
  final String body;
  final String okLabel;
  final IconData icon;
  final Color? accentColor;

  const InfoDialog({
    super.key,
    required this.title,
    required this.body,
    required this.okLabel,
    this.icon = Symbols.info_rounded,
    this.accentColor,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String body,
    required String okLabel,
    IconData icon = Symbols.info_rounded,
    Color? accentColor,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InfoDialog(
        title: title,
        body: body,
        okLabel: okLabel,
        icon: icon,
        accentColor: accentColor,
      ),
    );
  }

  @override
  State<InfoDialog> createState() => _InfoDialogState();
}

class _InfoDialogState extends State<InfoDialog> {
  late final GamepadNavigation _gamepadNav;

  @override
  void initState() {
    super.initState();
    _gamepadNav = GamepadNavigation(
      onSelectItem: () {
        if (mounted) Navigator.of(context).pop();
      },
      onBack: () {
        if (mounted) Navigator.of(context).pop();
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'info_dialog',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('info_dialog');
    _gamepadNav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = widget.accentColor ?? theme.colorScheme.primary;

    return AlertDialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
        side: BorderSide(color: accentColor.withValues(alpha: 0.3)),
      ),
      title: Row(
        children: [
          Icon(widget.icon, color: accentColor, size: 20.r),
          SizedBox(width: 8.r),
          Flexible(
            child: Text(
              widget.title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 14.r,
                color: accentColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        widget.body,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 11.r,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: theme.colorScheme.onPrimary,
            padding: EdgeInsets.symmetric(horizontal: 16.r, vertical: 8.r),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6.r),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18.r,
                height: 18.r,
                child: Image.asset(
                  'assets/images/gamepad/Xbox_A_button.png',
                  color: theme.colorScheme.onPrimary,
                  colorBlendMode: BlendMode.srcIn,
                ),
              ),
              SizedBox(width: 4.r),
              Text(
                widget.okLabel,
                style: TextStyle(
                  color: theme.colorScheme.onPrimary,
                  fontSize: 12.r,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
