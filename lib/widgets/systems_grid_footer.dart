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
  final VoidCallback? onSettings;
  final VoidCallback? onExtra;
  final String? enterLabel;
  final String? settingsLabel;
  final String? extraLabel;
  final String? extraIconPath;

  const SystemsGridFooter({
    super.key,
    required this.system,
    required this.onEnter,
    this.onSettings,
    this.onExtra,
    this.enterLabel,
    this.settingsLabel,
    this.extraLabel,
    this.extraIconPath,
  });

  @override
  bool get centerControls => false;

  @override
  bool get showVersion => false;

  @override
  Widget? buildLeftContent(BuildContext context) {
    if (system.folderName == 'create_collection') {
      return FooterLabelPill(
        label: system.title ?? AppLocale.createCollection.getString(context),
      );
    }

    return FooterLabelPill(
      label: system.isGame
          ? "${AppLocale.lastPlayed.getString(context)}: ${system.title}"
          : system.title ?? "",
      // Games and creation cards are one-offs, so only real systems/collections carry a count.
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
      // Extra action button (e.g. Create Collection [X])
      if (onExtra != null) ...[
        GamepadControl(
          label: extraLabel ?? AppLocale.createCollection.getString(context),
          iconPath: extraIconPath ?? 'assets/images/gamepad/Xbox_X_button.png',
          onTap: onExtra!,
          textColor: theme.colorScheme.onTertiaryFixed,
          backgroundColor: theme.colorScheme.tertiaryFixed,
        ),
        SizedBox(width: 8.r),
      ],

      // Settings/Options button (only for real systems and collections)
      if (!system.isGame &&
          system.folderName != 'create_collection' &&
          onSettings != null) ...[
        GamepadControl(
          label:
              settingsLabel ??
              (system.folderName?.startsWith('collection_') == true
                  ? AppLocale.edit.getString(context)
                  : AppLocale.settings.getString(context)),
          iconPath: 'assets/images/gamepad/Xbox_Menu_button.png',
          onTap: onSettings!,
          textColor: theme.colorScheme.onTertiaryFixed,
          backgroundColor: theme.colorScheme.tertiaryFixed,
        ),
        SizedBox(width: 8.r),
      ],

      // Enter/Play/Create button
      GamepadControl(
        label:
            enterLabel ??
            (system.folderName == 'create_collection'
                ? 'Create'
                : (system.isGame
                      ? AppLocale.play.getString(context)
                      : AppLocale.enter.getString(context))),
        iconPath: 'assets/images/gamepad/Xbox_A_button.png',
        onTap: onEnter,
        textColor: theme.colorScheme.onTertiary,
        backgroundColor: theme.colorScheme.tertiary,
      ),
    ];
  }
}
