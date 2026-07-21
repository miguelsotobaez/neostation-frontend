import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../models/game_model.dart';
import '../models/system_model.dart';
import '../sync/i_sync_provider.dart';
import '../themes/corner_radii.dart';
import 'game_action_button.dart';
import 'neo_sync_status_icon.dart';

/// Vertical action button column shared by the game list, grid, and carousel.
///
/// Renders back, favorite, view-mode, an optional NeoSync status icon, and the
/// game-settings shortcut as the last entry. Random is a Select + Y combo and
/// scraping is a Select + A combo, so neither has a dedicated legend entry.
class GameActionButtons extends StatelessWidget {
  final SystemModel system;
  final GameModel? selectedGame;
  final ISyncProvider? syncProvider;
  final VoidCallback onBack;
  final VoidCallback onFavorite;
  final VoidCallback onViewMode;
  final VoidCallback onSettings;

  const GameActionButtons({
    super.key,
    required this.system,
    this.selectedGame,
    this.syncProvider,
    required this.onBack,
    required this.onFavorite,
    required this.onViewMode,
    required this.onSettings,
  });

  @override
  Widget build(BuildContext context) {
    final selectedGame = this.selectedGame;
    final syncProvider = this.syncProvider;

    return Container(
      padding: EdgeInsets.all(6.r),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
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
          GameActionButton(
            iconPath: 'assets/images/gamepad/Xbox_B_button.png',
            symbol: Symbols.arrow_back_rounded,
            color: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            onTap: onBack,
          ),
          SizedBox(height: 6.r),
          GameActionButton(
            iconPath: 'assets/images/gamepad/Xbox_Y_button.png',
            symbol: Symbols.favorite_rounded,
            color: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            onTap: selectedGame != null ? onFavorite : null,
          ),
          SizedBox(height: 6.r),
          GameActionButton(
            iconPath: 'assets/images/gamepad/Xbox_X_button.png',
            symbol: Symbols.grid_view_rounded,
            color: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            onTap: onViewMode,
          ),
          SizedBox(height: 6.r),
          // Game settings — second-to-last option.
          GameActionButton(
            iconPath: 'assets/images/gamepad/Xbox_Menu_button.png',
            symbol: Symbols.settings_rounded,
            color: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            onTap: selectedGame != null ? onSettings : null,
          ),
          // Compact NeoSync status indicator — always the last option.
          if (syncProvider != null && selectedGame != null) ...[
            SizedBox(height: 12.r),
            NeoSyncStatusIcon(
              system: system,
              game: selectedGame,
              syncProvider: syncProvider,
              size: 24.0,
            ),
            SizedBox(height: 6.r),
          ] else
            SizedBox(height: 6.r),
        ],
      ),
    );
  }
}
