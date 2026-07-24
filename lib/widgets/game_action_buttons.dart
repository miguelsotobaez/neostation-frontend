import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/game_model.dart';
import '../models/system_model.dart';
import '../services/game_legend_visibility.dart';
import '../sync/i_sync_provider.dart';
import '../themes/corner_radii.dart';
import '../utils/gamepad_nav.dart';
import 'game_action_button.dart';
import 'horizontal_swipe.dart';
import 'neo_sync_status_icon.dart';

/// Vertical action button column shared by the game list, grid, and carousel.
///
/// Normally renders back, favorite, view-mode, an optional NeoSync status icon,
/// and the game-settings shortcut. While Select (View) is held it swaps to the
/// chord shortcuts it unlocks — A scrapes and Y picks a random game.
class GameActionButtons extends StatelessWidget {
  final SystemModel system;
  final GameModel? selectedGame;
  final ISyncProvider? syncProvider;
  final VoidCallback onBack;
  final VoidCallback onFavorite;
  final VoidCallback onViewMode;
  final VoidCallback onSettings;

  /// Select + Y — random game. Optional; the row is a legend when unset.
  final VoidCallback? onRandom;

  /// Select + A — scrape the highlighted game. Optional (list view only).
  final VoidCallback? onScrape;

  const GameActionButtons({
    super.key,
    required this.system,
    this.selectedGame,
    this.syncProvider,
    required this.onBack,
    required this.onFavorite,
    required this.onViewMode,
    required this.onSettings,
    this.onRandom,
    this.onScrape,
  });

  /// Whether the Select (View) chord layer has any shortcuts to reveal.
  bool get _hasChordActions => onScrape != null || onRandom != null;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GamepadNavigation.selectHeldNotifier,
      builder: (context, selectHeld, _) {
        return HorizontalSwipe(
          // Swipe left on the legend to hide it (touchscreen users have no
          // Select+B chord). Reshow is a swipe-right from the screen edge,
          // handled by the host view. Hiding slides the column off-screen via
          // GameLegendVisibility.
          onSwipeLeft: GameLegendVisibility.hide,
          child: Container(
            padding: EdgeInsets.all(6.r),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.9),
              borderRadius:
                  Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
                  BorderRadius.circular(14.r),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
                width: 1.r,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Touch affordance for the Select (View) modifier: tapping it
                // latches the chord layer on/off, mirroring holding Select on a
                // gamepad, so touchscreen users can reach the chord shortcuts.
                if (_hasChordActions) ...[
                  _buildViewToggle(context, active: selectHeld),
                  SizedBox(height: 6.r),
                ],
                ...(selectHeld
                    ? _buildChordButtons(context)
                    : _buildDefaultButtons(context)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The tappable Select (View) pill. Latches the shared [selectHeldNotifier]
  /// so both this column and the footer legend flip to the chord layer.
  Widget _buildViewToggle(BuildContext context, {required bool active}) {
    final scheme = Theme.of(context).colorScheme;
    return GameActionButton(
      iconPath: 'assets/images/gamepad/Xbox_View_button.png',
      symbol: active ? Symbols.close_rounded : Symbols.more_horiz_rounded,
      color: active ? scheme.secondary : scheme.primary,
      foregroundColor: active ? scheme.onSecondary : scheme.onPrimary,
      onTap: () => GamepadNavigation.selectHeldNotifier.value = !active,
    );
  }

  /// Wraps a chord action so tapping it auto-reverts the latched chord layer
  /// back to the default buttons (matches releasing Select on a gamepad).
  VoidCallback? _withRevert(VoidCallback? action) {
    if (action == null) return null;
    return () {
      action();
      GamepadNavigation.selectHeldNotifier.value = false;
    };
  }

  List<Widget> _buildDefaultButtons(BuildContext context) {
    final selectedGame = this.selectedGame;
    final syncProvider = this.syncProvider;
    final scheme = Theme.of(context).colorScheme;

    return [
      GameActionButton(
        iconPath: 'assets/images/gamepad/Xbox_B_button.png',
        symbol: Symbols.arrow_back_rounded,
        color: scheme.primary,
        foregroundColor: scheme.onPrimary,
        onTap: onBack,
      ),
      SizedBox(height: 6.r),
      GameActionButton(
        iconPath: 'assets/images/gamepad/Xbox_Y_button.png',
        symbol: Symbols.favorite_rounded,
        color: scheme.primary,
        foregroundColor: scheme.onPrimary,
        onTap: selectedGame != null ? onFavorite : null,
      ),
      SizedBox(height: 6.r),
      GameActionButton(
        iconPath: 'assets/images/gamepad/Xbox_X_button.png',
        symbol: Symbols.grid_view_rounded,
        color: scheme.primary,
        foregroundColor: scheme.onPrimary,
        onTap: onViewMode,
      ),
      SizedBox(height: 6.r),
      // Game settings — second-to-last option.
      GameActionButton(
        iconPath: 'assets/images/gamepad/Xbox_Menu_button.png',
        symbol: Symbols.settings_rounded,
        color: scheme.primary,
        foregroundColor: scheme.onPrimary,
        onTap: selectedGame != null ? onSettings : null,
      ),
      // Compact NeoSync status indicator — always the last option.
      // The icon renders nothing (SizedBox.shrink) when sync is unavailable
      // for this system, so its top spacing lives inside the widget to avoid
      // leaving a dangling gap below the settings button.
      if (syncProvider != null && selectedGame != null)
        NeoSyncStatusIcon(
          system: system,
          game: selectedGame,
          syncProvider: syncProvider,
          size: 24.0,
        ),
    ];
  }

  /// Shown while Select (View) is held: the chord shortcuts it unlocks.
  List<Widget> _buildChordButtons(BuildContext context) {
    final selectedGame = this.selectedGame;
    final scheme = Theme.of(context).colorScheme;

    return [
      // A — scrape the highlighted game. Secondary colors mark these as the
      // Select-held chord shortcuts, distinct from the primary default actions.
      GameActionButton(
        iconPath: 'assets/images/gamepad/Xbox_A_button.png',
        symbol: Symbols.cloud_download_rounded,
        color: scheme.secondary,
        foregroundColor: scheme.onSecondary,
        onTap: selectedGame != null ? _withRevert(onScrape) : null,
      ),
      SizedBox(height: 6.r),
      // Y — random game.
      GameActionButton(
        iconPath: 'assets/images/gamepad/Xbox_Y_button.png',
        symbol: Symbols.casino_rounded,
        color: scheme.secondary,
        foregroundColor: scheme.onSecondary,
        onTap: _withRevert(onRandom),
      ),
    ];
  }
}
