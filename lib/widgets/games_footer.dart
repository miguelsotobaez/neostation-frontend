import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'core_footer.dart';

/// Specific footer for the games screen
/// Inherits from CoreFooter to reuse common code
class GamesFooter extends CoreFooter {
  const GamesFooter({super.key});

  @override
  List<Widget> buildControls(BuildContext context) {
    // Swap the legend while Select (View) is held so the chord shortcuts are
    // revealed. Only the active navigation layer drives the notifier.
    return [
      ValueListenableBuilder<bool>(
        valueListenable: GamepadNavigation.selectHeldNotifier,
        builder: (context, selectHeld, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: selectHeld
                ? _buildSelectChordControls(context)
                : _buildDefaultControls(context),
          );
        },
      ),
    ];
  }

  List<Widget> _buildDefaultControls(BuildContext context) {
    final theme = Theme.of(context);

    return [
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_D-pad_ALL.png',
        label: AppLocale.hintNavigate.getString(context),
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_A_button.png',
        label: AppLocale.hintPlay.getString(context),
        textColor: Colors.white,
        backgroundColor: const Color(0xFF2ECC71),
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_Y_button.png',
        label: AppLocale.hintFavorite.getString(context),
        backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.8),
        textColor: Colors.white,
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_X_button.png',
        label: AppLocale.hintViewMode.getString(context),
        backgroundColor: theme.colorScheme.primary,
        textColor: Colors.white,
      ),
      SizedBox(width: 8.r),
      // Hint that holding Select (View) reveals more actions.
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_View_button.png',
        label: AppLocale.hintMoreActions.getString(context),
        backgroundColor: theme.colorScheme.tertiaryContainer,
        textColor: theme.colorScheme.onTertiaryContainer,
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_Menu_button.png',
        label: AppLocale.hintSettings.getString(context),
        backgroundColor: theme.colorScheme.tertiary,
        textColor: theme.colorScheme.onTertiary,
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_B_button.png',
        label: AppLocale.hintBack.getString(context),
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.3,
        ),
        textColor: theme.colorScheme.onSurface,
      ),
    ];
  }

  /// Controls shown while Select (View) is held — the chord shortcuts.
  List<Widget> _buildSelectChordControls(BuildContext context) {
    final theme = Theme.of(context);

    return [
      // Select (View) shown as the active modifier.
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_View_button.png',
        label: AppLocale.hintMoreActions.getString(context),
        backgroundColor: theme.colorScheme.primary,
        textColor: theme.colorScheme.onPrimary,
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_A_button.png',
        label: AppLocale.hintScrape.getString(context),
        textColor: Colors.white,
        backgroundColor: const Color(0xFF2ECC71),
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_Y_button.png',
        label: AppLocale.hintRandom.getString(context),
        backgroundColor: theme.colorScheme.secondary.withValues(alpha: 0.8),
        textColor: Colors.white,
      ),
    ];
  }
}
