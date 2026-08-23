import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/my_systems.dart';
import 'core_footer.dart';
import 'footer_label_pill.dart';

/// Unified footer for the systems grid
/// Implements the left-text and right-controls layout
class SystemsGridFooter extends CoreFooter {
  final SystemInfo system;
  final VoidCallback onEnter;
  final VoidCallback onSettings;

  const SystemsGridFooter({
    super.key,
    required this.system,
    required this.onEnter,
    required this.onSettings,
  });

  @override
  bool get centerControls => false;

  @override
  bool get showVersion => false;

  @override
  Widget? buildLeftContent(BuildContext context) {
    return FooterLabelPill(
      label: system.isGame
          ? "${AppLocale.lastPlayed.getString(context)}: ${system.title}"
          : system.title ?? "",
      // Games are one-offs, so only real systems carry a count.
      countText: system.isGame
          ? null
          : "${system.numOfRoms} ${system.folderName == 'android'
                ? AppLocale.apps.getString(context)
                : system.folderName == 'music'
                ? AppLocale.tracks.getString(context)
                : AppLocale.games.getString(context)}",
    );
  }

  @override
  List<Widget> buildControls(BuildContext context) {
    final theme = Theme.of(context);

    return [
      // Settings button (only for real systems, not for the 'All Games' shortcut if desired)
      if (!system.isGame)
        GamepadControl(
          label: AppLocale.settings.getString(context),
          iconPath: 'assets/images/gamepad/Xbox_Menu_button.png',
          onTap: onSettings,
          textColor: theme.colorScheme.onTertiaryFixed,
          backgroundColor: theme.colorScheme.tertiaryFixed,
        ),
      if (!system.isGame) SizedBox(width: 8.r),
      // Enter/Play button
      GamepadControl(
        label: system.isGame
            ? AppLocale.play.getString(context)
            : AppLocale.enter.getString(context),
        iconPath: 'assets/images/gamepad/Xbox_A_button.png',
        onTap: onEnter,
        textColor: theme.colorScheme.onTertiary,
        backgroundColor: theme.colorScheme.tertiary,
      ),
    ];
  }
}
