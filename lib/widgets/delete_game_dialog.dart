import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';

/// A gamepad-friendly confirmation dialog that warns about permanent game
/// deletion. Shared by the game details settings tab and the game settings
/// dialog. Pops with `true` when confirmed, `false` otherwise.
class DeleteGameDialog extends StatefulWidget {
  final String gameName;
  final String romName;

  const DeleteGameDialog({
    super.key,
    required this.gameName,
    required this.romName,
  });

  @override
  State<DeleteGameDialog> createState() => _DeleteGameDialogState();
}

class _DeleteGameDialogState extends State<DeleteGameDialog> {
  late final GamepadNavigation _gamepadNav;

  @override
  void initState() {
    super.initState();
    _gamepadNav = GamepadNavigation(
      onSelectItem: () {
        if (mounted) Navigator.of(context).pop(true);
      },
      onBack: () {
        if (mounted) Navigator.of(context).pop(false);
      },
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'delete_game_dialog',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('delete_game_dialog');
    _gamepadNav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final errorColor = theme.colorScheme.error;

    return AlertDialog(
      backgroundColor: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
        side: BorderSide(color: errorColor.withValues(alpha: 0.3)),
      ),
      title: Row(
        children: [
          Icon(Symbols.delete_rounded, color: errorColor, size: 20.r),
          SizedBox(width: 8.r),
          Flexible(
            child: Text(
              AppLocale.deleteGame.getString(context),
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 14.r,
                color: errorColor,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"${widget.gameName}"',
            style: theme.textTheme.bodyLarge?.copyWith(
              fontSize: 13.r,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 2.r),
          Text(
            widget.romName,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          SizedBox(height: 8.r),
          Text(
            AppLocale.deleteGameConfirmBody.getString(context),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 11.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18.r,
                height: 18.r,
                child: Image.asset(
                  'assets/images/gamepad/Xbox_B_button.png',
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  colorBlendMode: BlendMode.srcIn,
                ),
              ),
              SizedBox(width: 4.r),
              Text(
                AppLocale.cancel.getString(context),
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12.r,
                ),
              ),
            ],
          ),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: errorColor,
            foregroundColor: theme.colorScheme.onError,
            padding: EdgeInsets.symmetric(horizontal: 16.r, vertical: 8.r),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6.r),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18.r,
                height: 18.r,
                child: Image.asset(
                  'assets/images/gamepad/Xbox_A_button.png',
                  color: theme.colorScheme.onError,
                  colorBlendMode: BlendMode.srcIn,
                ),
              ),
              SizedBox(width: 4.r),
              Text(
                AppLocale.deleteGameConfirm.getString(context),
                style: TextStyle(
                  color: theme.colorScheme.onError,
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
