import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/my_systems.dart';
import '../themes/corner_radii.dart';
import 'core_footer.dart';

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
    final theme = Theme.of(context);

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.only(top: 4.r, bottom: 4.r, left: 12.r, right: 6.r),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryFixed,
          borderRadius:
              Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
              BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.3),
              blurRadius: 3.r,
              offset: Offset(2.0.r, 2.0.r),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                system.isGame
                    ? "${AppLocale.lastPlayed.getString(context)}: ${system.title}"
                    : system.title ?? "",
                style: TextStyle(
                  color: theme.colorScheme.onTertiaryFixed,
                  fontSize: 14.r,
                  fontWeight: FontWeight.bold,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (!system.isGame) ...[
              SizedBox(width: 10.r),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 2.r),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius:
                      Theme.of(
                        context,
                      ).extension<CornerRadii>()?.radiusInternal ??
                      BorderRadius.circular(12.r),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.3),
                      blurRadius: 3.r,
                      offset: Offset(2.0.r, 2.0.r),
                    ),
                  ],
                ),
                child: Text(
                  "${system.numOfRoms} ${system.folderName == 'android'
                      ? AppLocale.apps.getString(context)
                      : system.folderName == 'music'
                      ? AppLocale.tracks.getString(context)
                      : AppLocale.games.getString(context)}",
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 10.r,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5.r,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
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
