import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../l10n/app_locale.dart';
import 'core_footer.dart';
import 'footer_label_pill.dart';

/// Footer for the RomM browser's platform and ROM views.
///
/// The app's footer shape — focused item in a pill on the left, gamepad
/// controls on the right — kept here after the systems screen dropped its own
/// footer to give the cards that vertical space. RomM's grid cards are artwork
/// only, so this is the one place the focused item is named. Both views offer
/// Y to sync the whole source and B to step back.
///
/// The ROM view's X layout toggle used to live on the vertical action rail
/// alone. With the rail gone this footer is the only on-screen route to it, so
/// the ROM views pass [onToggleView]; the platform view leaves it null and
/// keeps the shorter legend.
///
/// The pill always names the *focused* item: the platform in the platform view,
/// the focused ROM in the ROM views (where the grid's cards are artwork
/// only, so this is the one place the game is named).
class RommBrowseFooter extends CoreFooter {
  /// Name shown in the pill: the focused platform, or the open platform /
  /// collection while its ROMs are being browsed.
  final String label;

  /// Optional count chip (e.g. "128 games").
  final String? countText;

  /// Label for the A button — "Enter" in the platform view, "Download" in the
  /// ROM view.
  final String confirmLabel;
  final VoidCallback onConfirm;
  final VoidCallback onBack;

  /// Bulk sync (Y) — downloads the whole focused/open platform or collection,
  /// or cancels the sync already running. Null where there is nothing to sync
  /// (an empty list, or no connection).
  final VoidCallback? onSyncAll;

  /// Swaps the Y label from "Sync all" to "Cancel sync" while one is running,
  /// since the same button does both.
  final bool isSyncing;

  /// X — switches the ROM view between list and grid. Null in the platform
  /// view, which has no layout to switch.
  final VoidCallback? onToggleView;

  const RommBrowseFooter({
    super.key,
    required this.label,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onBack,
    this.countText,
    this.onSyncAll,
    this.isSyncing = false,
    this.onToggleView,
  });

  @override
  bool get centerControls => false;

  @override
  bool get showVersion => false;

  @override
  Widget? buildLeftContent(BuildContext context) =>
      FooterLabelPill(label: label, countText: countText);

  @override
  List<Widget> buildControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // A sits far right in every footer in the app, so the confirm action is
    // always in the same place; the lesser actions queue up to its left.
    return [
      if (onSyncAll != null) ...[
        GamepadControl(
          label: (isSyncing ? AppLocale.rommSyncCancel : AppLocale.rommSyncAll)
              .getString(context),
          iconPath: 'assets/images/gamepad/Xbox_Y_button.png',
          onTap: onSyncAll,
          textColor: scheme.onTertiaryFixed,
          backgroundColor: scheme.tertiaryFixed,
        ),
        SizedBox(width: 8.r),
      ],
      if (onToggleView != null) ...[
        GamepadControl(
          label: AppLocale.viewMode.getString(context),
          iconPath: 'assets/images/gamepad/Xbox_X_button.png',
          onTap: onToggleView,
          textColor: scheme.onSurface,
          backgroundColor: scheme.surfaceContainerHighest.withValues(
            alpha: 0.3,
          ),
        ),
        SizedBox(width: 8.r),
      ],
      GamepadControl(
        label: AppLocale.hintBack.getString(context),
        iconPath: 'assets/images/gamepad/Xbox_B_button.png',
        onTap: onBack,
        textColor: scheme.onSurface,
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        label: confirmLabel,
        iconPath: 'assets/images/gamepad/Xbox_A_button.png',
        onTap: onConfirm,
        textColor: scheme.onTertiary,
        backgroundColor: scheme.tertiary,
      ),
    ];
  }
}
