import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'core_footer.dart';

/// Specific footer for the games screen
/// Inherits from CoreFooter to reuse common code
class GamesFooter extends CoreFooter {
  const GamesFooter({super.key});

  @override
  List<Widget> buildControls(BuildContext context) {
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
      // Select (View) held as a modifier: + A scrapes, + Y picks a random game.
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_View_button.png',
        label: '+A ${AppLocale.hintScrape.getString(context)}',
        backgroundColor: theme.colorScheme.tertiaryContainer,
        textColor: theme.colorScheme.onTertiaryContainer,
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        iconPath: 'assets/images/gamepad/Xbox_View_button.png',
        label: '+Y ${AppLocale.hintRandom.getString(context)}',
        backgroundColor: theme.colorScheme.errorContainer.withValues(
          alpha: 0.6,
        ),
        textColor: theme.colorScheme.onErrorContainer,
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
}
