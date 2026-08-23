import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../l10n/app_locale.dart';
import 'core_footer.dart';
import 'footer_label_pill.dart';

/// Footer for the RomM browser's platform and ROM views.
///
/// Same shape and styling as [SystemsGridFooter] — focused item in a pill on
/// the left, gamepad controls on the right — so the remote library reads like
/// the local one. Only the controls differ: both views offer Y to sync the
/// whole source and B to step back.
///
/// The ROM view's X layout toggle is deliberately *not* here: it lives on the
/// vertical legend ([RommActionButtons]) alone, so the footer stays short
/// enough to read at a glance on a handheld.
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

  const RommBrowseFooter({
    super.key,
    required this.label,
    required this.confirmLabel,
    required this.onConfirm,
    required this.onBack,
    this.countText,
    this.onSyncAll,
    this.isSyncing = false,
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
