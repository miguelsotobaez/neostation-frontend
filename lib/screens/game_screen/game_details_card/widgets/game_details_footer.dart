import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/game_legend_visibility.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/themes/app_themes.dart';
import '../../../../models/system_model.dart';
import '../../../../models/game_model.dart';
import '../../../../models/retro_achievements_game_info.dart';
import '../../../../sync/i_sync_provider.dart';
import 'package:neostation/themes/chrome_surface.dart';
import '../../../../themes/corner_radii.dart';
import '../../../../utils/game_utils.dart';
import '../../../../widgets/marquee_text.dart';
import '../../music/music_player.dart';

/// A sticky footer component for the game details card that provides actionable controls and status summaries.
///
/// Manages high-level game interactions (Play), summarizes cloud synchronization
/// health, and provides quick access to trophy progress. Dynamically adjusts for specialized
/// systems like the Music Player.
class GameDetailsFooter extends StatelessWidget {
  final SystemModel system;
  final GameModel game;
  final bool isMusicSystem;
  final bool hasScreenScraper;
  final bool isSecondaryScreenActive;
  final bool cloudSyncEnabled;
  final ISyncProvider syncProvider;
  final AnimationController? syncIconController;
  final VoidCallback onPlayGame;
  final VoidCallback onShowAchievements;
  final bool hasRetroAchievements;
  final bool isLoadingAchievements;
  final GameInfoAndUserProgress? currentGameInfo;

  const GameDetailsFooter({
    super.key,
    required this.system,
    required this.game,
    required this.isMusicSystem,
    required this.hasScreenScraper,
    required this.isSecondaryScreenActive,
    required this.cloudSyncEnabled,
    required this.syncProvider,
    this.syncIconController,
    required this.onPlayGame,
    required this.onShowAchievements,
    required this.hasRetroAchievements,
    required this.isLoadingAchievements,
    this.currentGameInfo,
  });

  @override
  Widget build(BuildContext context) {
    // Scenario 1: Specialized Music Player UI.
    if (isMusicSystem) {
      return Positioned(
        bottom: -0.5.r,
        left: -0.5.r,
        right: -0.5.r,
        child: MusicPlayer(systemColor: system.colorAsColor),
      );
    }

    // Scenario 2: Standard Game Metadata UI.
    return Positioned(
      bottom: -0.5.r,
      left: -0.5.r,
      right: -0.5.r,
      height: 105.r,
      child: ClipRRect(
        child: RepaintBoundary(
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12.r),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Identity Section: Title and ROM Filename.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: RepaintBoundary(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            MarqueeText(
                              text: GameUtils.formatGameName(game.name),
                              isActive: true,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20.r,
                                fontWeight: FontWeight.bold,
                                shadows: [
                                  Shadow(
                                    blurRadius: 1.r,
                                    color: Colors.black,
                                    offset: const Offset(2, 2),
                                  ),
                                ],
                              ),
                            ),
                            // Always reserve the ROM-filename subtitle's line
                            // height so the action row below keeps a constant
                            // baseline. Unscraped games have no subtitle; without
                            // this reservation the rating/RA pill + PLAY button
                            // float up one line. The empty string still lays out
                            // a full line box via the shared strut/style.
                            Text(
                              game.showRomFileNameSubtitle ? game.romname : '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              strutStyle: StrutStyle(
                                fontSize: 12.r,
                                height: 1.15,
                                forceStrutHeight: true,
                              ),
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 12.r,
                                fontWeight: FontWeight.w400,
                                height: 1.15,
                                shadows: [
                                  Shadow(
                                    blurRadius: 1.r,
                                    color: Colors.black,
                                    offset: const Offset(2, 2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 8.r),

                // Actionable Section: Compact status indicators and primary Play button.
                ExcludeFocus(
                  child: Row(
                    children: [
                      // Game rating.
                      if (game.rating > 0) ...[
                        _SteamStyleRating(game: game),
                        SizedBox(width: 8.r),
                      ],

                      // RetroAchievements Progress. When the legend is hidden
                      // the row gains width on the left; the indicator eases out
                      // to fill the gap to PLAY (LayoutBuilder gives it a
                      // concrete target width so the change animates instead of
                      // snapping). When shown it rests at its natural width,
                      // left-aligned, and the rest of the slot stays empty.
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) => Align(
                            alignment: Alignment.centerLeft,
                            child: _buildCompactAchievementsIndicator(
                              context,
                              availableWidth: constraints.maxWidth,
                              hasPlayTime:
                                  GameUtils.formatPlayTime(
                                    game.playTime ?? 0,
                                  ) !=
                                  '0s',
                            ),
                          ),
                        ),
                      ),
                      // Accumulated play time, shown as its own pill to the
                      // left of PLAY (only once the game has been played).
                      if (GameUtils.formatPlayTime(game.playTime ?? 0) !=
                          '0s') ...[
                        SizedBox(width: 8.r),
                        _PlayTimePill(game: game),
                      ],

                      // Consistent 8.r gap before PLAY, matching the spacing
                      // between the rating, RA and play-time pills.
                      SizedBox(width: 8.r),

                      // Primary Launch Control.
                      _buildPlayButtonCompact(context),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// High-contrast primary button for launching the emulator.
  ///
  /// Includes visual feedback for gamepad focus and displays accumulated play-time statistics.
  Widget _buildPlayButtonCompact(BuildContext context) {
    return Builder(
      builder: (context) {
        final isFocused = Focus.of(context).hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 104.r,
          height: 45.r,
          decoration: BoxDecoration(
            color: isFocused
                ? const Color(0xFF36F184)
                : const Color(0xFF2ECC71),
            borderRadius:
                Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
                BorderRadius.circular(14.r),
            border: Border.all(color: Color(0xFF36F184), width: 1.r),
            boxShadow: [
              BoxShadow(
                color: Theme.of(
                  context,
                ).colorScheme.shadow.withValues(alpha: 0.1),
                blurRadius: 4.r,
                offset: Offset(2.0.r, 2.0.r),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              canRequestFocus: false,
              focusColor: Colors.transparent,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.white.withValues(alpha: 0.1),
              borderRadius:
                  Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
                  BorderRadius.circular(14.r),
              onTap: () {
                SfxService().playEnterSound();
                onPlayGame();
              },
              child: Padding(
                padding: EdgeInsets.only(left: 0.r, right: 10.r),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      'assets/images/gamepad/Xbox_A_button.png',
                      width: 32.r,
                      height: 32.r,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                    SizedBox(width: 8.r),
                    Text(
                      AppLocale.playButton.getString(context),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 14.r,
                        letterSpacing: 1.5,
                        height: 1.0,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Resolves the current RetroAchievements progress into a compact visual badge.
  Widget _buildCompactAchievementsIndicator(
    BuildContext context, {
    required double availableWidth,
    required bool hasPlayTime,
  }) {
    if (!hasRetroAchievements) return const SizedBox.shrink();

    // The badge fills its (Expanded) slot when the legend is hidden, or when
    // there is no play-time pill claiming the space to its right (otherwise it
    // would leave dead space between itself and PLAY). When neither applies it
    // rests at 120.r. The width is animated so toggling eases in/out.
    final bool legendHidden = GameLegendVisibility.hidden.value;
    final bool expand = legendHidden || !hasPlayTime;
    final bool noAchievements =
        !isLoadingAchievements &&
        (currentGameInfo == null || currentGameInfo!.numAchievements == 0);

    final int awarded = currentGameInfo?.numAwardedToUser ?? 0;
    final int total = currentGameInfo?.numAchievements ?? 0;
    final double progress = total > 0 ? awarded / total : 0.0;

    final String progressText = isLoadingAchievements
        ? AppLocale.loading.getString(context)
        : (noAchievements
              ? AppLocale.noAchievements.getString(context)
              : '$awarded/$total');

    final theme = Theme.of(context);
    final Color statusColor = noAchievements
        ? theme.colorScheme.onSurface
        : Colors.orange;

    final String? gameIconUrl = currentGameInfo?.imageIcon.isNotEmpty == true
        ? 'https://media.retroachievements.org${currentGameInfo!.imageIcon}'
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          SfxService().playNavSound();
          onShowAchievements();
        },
        canRequestFocus: false,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.r),
        // Drive the width from a single 0..1 factor on the same 250ms /
        // easeOutCubic timing as the sidebar margin, so the pill expands in
        // lockstep with the legend slide (one motion) rather than shifting
        // into place first and then easing its width (two steps).
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: expand ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          builder: (context, t, child) => Container(
            width: 120.r + (availableWidth - 120.r) * t,
            height: 45.r,
            decoration: BoxDecoration(
              color: ChromeSurface.fill(context),
              borderRadius:
                  Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
                  BorderRadius.circular(14.r),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
                width: 1.r,
              ),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(
                    context,
                  ).colorScheme.shadow.withValues(alpha: 0.1),
                  blurRadius: 4.r,
                  offset: Offset(2.0.r, 2.0.r),
                ),
              ],
            ),
            child: child,
          ),
          child: Padding(
            // Symmetric 8.r horizontal inset so neither the trophy icon nor the
            // progress bar hugs the pill border. The progress column is always
            // Expanded, so it simply absorbs the padding at any pill width (the
            // shown/hidden width animation never overflows).
            padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 4.r),
            child: Row(
              children: [
                // RetroAchievements game icon.
                ClipRRect(
                  borderRadius:
                      Theme.of(
                        context,
                      ).extension<CornerRadii>()?.radiusInternal ??
                      BorderRadius.circular(14.r),
                  child: Container(
                    width: 32.r,
                    height: 32.r,
                    color: theme.colorScheme.surface,
                    child: gameIconUrl != null
                        ? Image.network(
                            gameIconUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Symbols.emoji_events_rounded,
                              color: statusColor,
                              size: 16.r,
                            ),
                          )
                        : Icon(
                            Symbols.emoji_events_rounded,
                            color: statusColor,
                            size: 16.r,
                          ),
                  ),
                ),
                SizedBox(width: 8.r),
                // Progress bar and achievement count. When the legend is hidden
                // the pill stretches, so let this column (and its bar) fill the
                // extra width via Expanded; otherwise keep the fixed 70.r width.
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          progressText.toUpperCase(),
                          style: TextStyle(
                            color: theme.colorScheme.onSurface,
                            fontSize: 10.r,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(height: 4.r),
                      // Hold the bar short of the pill's right edge so it
                      // doesn't run all the way across — mirrors the grid/
                      // carousel pill's right margin under the progress count.
                      Padding(
                        padding: EdgeInsets.only(right: 10.r),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(4.r),
                          child: LinearProgressIndicator(
                            value: isLoadingAchievements ? null : progress,
                            minHeight: 5.r,
                            backgroundColor: theme.colorScheme.onSurface
                                .withValues(alpha: 0.1),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              statusColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A Steam-inspired rating badge that interpolates color based on the score intensity.
class _SteamStyleRating extends StatelessWidget {
  final GameModel game;

  const _SteamStyleRating({required this.game});

  @override
  Widget build(BuildContext context) {
    // Normalizes a 0-20 score to a 0.0-10.0 scale for color interpolation.
    final ratingValue = (game.rating / 2).clamp(0.0, 10.0);
    final colorRatio = (ratingValue - 1) / 9;
    final customColors = AppThemes.getCustomColors(context);
    final ratingColor = Color.lerp(
      customColors.errorColor,
      customColors.successColor,
      colorRatio,
    )!;

    return Container(
      height: 45.r,
      padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 6.r),
      decoration: BoxDecoration(
        color: ChromeSurface.fill(context),
        borderRadius:
            Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
            BorderRadius.circular(14.r),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1.r,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.5),
            blurRadius: 3.r,
            offset: Offset(2.0.r, 2.0.r),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(Symbols.star_rounded, color: ratingColor, size: 24.r),
          SizedBox(width: 4.r),
          // Reserve width for the widest possible value ("10") so the pill
          // stays a static size regardless of the current score (e.g. "1"
          // no longer renders narrower than "10"). Scale/font-independent.
          Stack(
            alignment: Alignment.centerLeft,
            children: [
              Opacity(
                opacity: 0,
                child: Text(
                  '10',
                  style: TextStyle(fontSize: 22.r, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                ratingValue.toStringAsFixed(0),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 22.r,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact pill showing the accumulated play time for a game, styled to match
/// the rating pill. Sits to the left of the PLAY button.
class _PlayTimePill extends StatelessWidget {
  final GameModel game;

  const _PlayTimePill({required this.game});

  /// Formats accumulated seconds as a zero-padded HH:MM:SS clock.
  String _formatClock(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${pad(h)}:${pad(m)}:${pad(s)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 45.r,
      padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 4.r),
      decoration: BoxDecoration(
        color: ChromeSurface.fill(context),
        borderRadius:
            Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
            BorderRadius.circular(14.r),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline,
          width: 1.r,
        ),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.5),
            blurRadius: 3.r,
            offset: Offset(2.0.r, 2.0.r),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Symbols.schedule_rounded,
            color: Theme.of(context).colorScheme.onSurface,
            size: 14.r,
          ),
          SizedBox(height: 1.r),
          Text(
            _formatClock(game.playTime ?? 0),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 10.r,
              fontWeight: FontWeight.w800,
              height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
