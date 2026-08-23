import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../services/game_legend_visibility.dart';
import '../themes/corner_radii.dart';
import 'game_action_button.dart';
import 'horizontal_swipe.dart';

/// Vertical action-button column for the RomM browser's ROM views.
///
/// The remote sibling of [GameActionButtons]: same column, same buttons, same
/// swipe-to-hide behaviour, driven by the same shared [GameLegendVisibility]
/// flag so hiding the legend in the local library hides it here too. Only the
/// verbs differ — a remote ROM has no favourite, no per-game settings and no
/// sync state, so the column is back, view mode and download.
class RommActionButtons extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onViewMode;

  /// A — downloads the focused ROM, or cancels a transfer already running on
  /// it. Null when nothing is focused (empty library), which greys the button.
  final VoidCallback? onDownload;

  /// Swaps the download button for a cancel affordance while the focused ROM is
  /// transferring, mirroring the on-tile control.
  final bool isDownloading;

  /// Marks the focused ROM as already present on disk — the button then reads
  /// as a completed state rather than an available action.
  final bool isDownloaded;

  /// Y — downloads the whole open platform/collection, or cancels the sync
  /// already running. Null hides the button entirely.
  final VoidCallback? onSyncAll;

  /// Swaps the sync button for a stop affordance while a bulk sync is running.
  final bool isSyncing;

  const RommActionButtons({
    super.key,
    required this.onBack,
    required this.onViewMode,
    this.onDownload,
    this.isDownloading = false,
    this.isDownloaded = false,
    this.onSyncAll,
    this.isSyncing = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return HorizontalSwipe(
      // Swipe left on the legend to hide it (touchscreen users have no Select+B
      // chord). Reshow is a swipe-right from the screen edge, handled by the
      // host view via LegendEdgeReshowZone.
      onSwipeLeft: GameLegendVisibility.hide,
      child: Container(
        padding: EdgeInsets.all(6.r),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.9),
          borderRadius:
              Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
              BorderRadius.circular(14.r),
          border: Border.all(color: scheme.outline, width: 1.r),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GameActionButton(
              iconPath: 'assets/images/gamepad/Xbox_B_button.png',
              symbol: Symbols.arrow_back_rounded,
              color: scheme.tertiaryFixed,
              foregroundColor: scheme.onTertiaryFixed,
              sound: GameActionButtonSound.back,
              onTap: onBack,
            ),
            SizedBox(height: 6.r),
            GameActionButton(
              iconPath: 'assets/images/gamepad/Xbox_X_button.png',
              symbol: Symbols.grid_view_rounded,
              color: scheme.tertiaryFixed,
              foregroundColor: scheme.onTertiaryFixed,
              sound: GameActionButtonSound.nav,
              onTap: onViewMode,
            ),
            if (onSyncAll != null) ...[
              SizedBox(height: 6.r),
              GameActionButton(
                iconPath: 'assets/images/gamepad/Xbox_Y_button.png',
                symbol: isSyncing
                    ? Symbols.stop_circle_rounded
                    : Symbols.cloud_download_rounded,
                color: scheme.tertiaryFixed,
                foregroundColor: scheme.onTertiaryFixed,
                sound: isSyncing
                    ? GameActionButtonSound.back
                    : GameActionButtonSound.enter,
                onTap: onSyncAll,
              ),
            ],
            SizedBox(height: 6.r),
            GameActionButton(
              iconPath: 'assets/images/gamepad/Xbox_A_button.png',
              symbol: isDownloading
                  ? Symbols.close_rounded
                  : (isDownloaded
                        ? Symbols.check_circle_rounded
                        : Symbols.download_rounded),
              color: scheme.tertiaryFixed,
              foregroundColor: scheme.onTertiaryFixed,
              sound: isDownloading
                  ? GameActionButtonSound.back
                  : GameActionButtonSound.enter,
              onTap: onDownload,
            ),
          ],
        ),
      ),
    );
  }
}
