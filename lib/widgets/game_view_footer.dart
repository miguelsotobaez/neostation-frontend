import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/retro_achievements_game_info.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/themes/app_themes.dart';
import 'package:neostation/utils/game_utils.dart';
import 'package:neostation/widgets/marquee_text.dart';
import '../../themes/corner_radii.dart';

/// A reusable footer used by the game grid and carousel views.
///
/// Mirrors the layout of the details list footer: the game name and optional ROM
/// subtitle are anchored to the left, while the rating, RetroAchievements
/// summary, and Play button are grouped on the right.
class GameViewFooter extends StatelessWidget {
  final GameModel game;
  final VoidCallback onPlay;
  final bool hasRetroAchievements;
  final bool isLoadingAchievements;
  final GameInfoAndUserProgress? currentGameInfo;
  final VoidCallback? onShowAchievements;

  /// Toggles global video sound. The grid and carousel have no video surface of
  /// their own — the preview plays on the secondary display — so this pill is
  /// their only mute affordance, mirroring the Select hint on the details card.
  /// Omit it to hide the pill.
  final VoidCallback? onToggleMute;

  const GameViewFooter({
    super.key,
    required this.game,
    required this.onPlay,
    this.hasRetroAchievements = false,
    this.isLoadingAchievements = false,
    this.currentGameInfo,
    this.onShowAchievements,
    this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 8.r),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Identity section: title and optional ROM subtitle.
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                MarqueeText(
                  text: GameUtils.formatGameName(game.name),
                  isActive: true,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18.r,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        blurRadius: 2.r,
                        color: Colors.black,
                        offset: const Offset(0, 0),
                      ),
                    ],
                  ),
                ),
                // Always reserve the ROM-filename subtitle's line height so the
                // identity column stays a constant height. Unscraped games have
                // no subtitle; without this reservation the shorter column
                // re-centers the rating/RA pill + PLAY row upward. The empty
                // string still lays out a full line box via the forced strut.
                Text(
                  game.showRomFileNameSubtitle ? game.romname : '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  strutStyle: StrutStyle(
                    fontSize: 12.r,
                    forceStrutHeight: true,
                  ),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontSize: 12.r,
                    fontWeight: FontWeight.w400,
                    shadows: [
                      Shadow(
                        blurRadius: 2.r,
                        color: Colors.black.withValues(alpha: 0.45),
                        offset: const Offset(2, 2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(width: 12.r),

          // Action/status section: rating, RetroAchievements, play.
          ExcludeFocus(
            child: Row(
              children: [
                if (onToggleMute != null) ...[
                  _MuteHintPill(onToggleMute: onToggleMute!),
                  SizedBox(width: 6.r),
                ],
                if (game.rating > 0) ...[
                  _SteamStyleRating(game: game),
                  SizedBox(width: 6.r),
                ],
                if (hasRetroAchievements) ...[
                  _CompactAchievementsIndicator(
                    isLoading: isLoadingAchievements,
                    gameInfo: currentGameInfo,
                    onTap: onShowAchievements,
                  ),
                  SizedBox(width: 6.r),
                ],
                // Accumulated play time as its own pill to the left of PLAY
                // (only once the game has been played), mirroring the details
                // card footer.
                if (GameUtils.formatPlayTime(game.playTime ?? 0) != '0s') ...[
                  _PlayTimePill(game: game),
                  SizedBox(width: 6.r),
                ],
                _buildPlayButton(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayButton(BuildContext context) {
    return Builder(
      builder: (context) {
        final radii =
            Theme.of(context).extension<CornerRadii>() ?? CornerRadii.m();
        final isFocused = Focus.of(context).hasFocus;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 32.r,
          decoration: BoxDecoration(
            color: isFocused
                ? const Color(0xFF36F184)
                : const Color(0xFF2ECC71),
            borderRadius: radii.radiusExternal,
            border: Border.all(color: const Color(0xFF36F184), width: 1.r),
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
              borderRadius: radii.radiusExternal,
              onTap: () {
                SfxService().playEnterSound();
                onPlay();
              },
              child: Padding(
                padding: EdgeInsets.only(left: 8.r, right: 10.r),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/gamepad/Xbox_A_button.png',
                      width: 20.r,
                      height: 20.r,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                    SizedBox(width: 5.r),
                    Text(
                      AppLocale.playButton.getString(context),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.r,
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
}

/// A Steam-inspired rating badge that interpolates color based on the score intensity.
/// Compact pill showing accumulated play time as a clock (HH:MM:SS), sized to
/// match the rating / achievements pills in this footer.
class _PlayTimePill extends StatelessWidget {
  final GameModel game;

  const _PlayTimePill({required this.game});

  String _formatClock(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String pad(int v) => v.toString().padLeft(2, '0');
    return '${pad(h)}:${pad(m)}:${pad(s)}';
  }

  @override
  Widget build(BuildContext context) {
    final radii = Theme.of(context).extension<CornerRadii>() ?? CornerRadii.m();
    return Container(
      height: 32.r,
      padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 4.r),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: radii.radiusExternal,
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
          Icon(
            Symbols.schedule_rounded,
            color: Theme.of(context).colorScheme.onSurface,
            size: 15.r,
          ),
          SizedBox(width: 4.r),
          Text(
            _formatClock(game.playTime ?? 0),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 12.r,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _SteamStyleRating extends StatelessWidget {
  final GameModel game;

  const _SteamStyleRating({required this.game});

  @override
  Widget build(BuildContext context) {
    final radii = Theme.of(context).extension<CornerRadii>() ?? CornerRadii.m();
    final ratingValue = (game.rating / 2).clamp(0.0, 10.0);
    final colorRatio = (ratingValue - 1) / 9;
    final customColors = AppThemes.getCustomColors(context);
    final ratingColor = Color.lerp(
      customColors.errorColor,
      customColors.successColor,
      colorRatio,
    )!;

    return Container(
      height: 32.r,
      padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 4.r),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        borderRadius: radii.radiusExternal,
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
          Icon(Symbols.star_rounded, color: ratingColor, size: 15.r),
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
                  style: TextStyle(fontSize: 13.r, fontWeight: FontWeight.w900),
                ),
              ),
              Text(
                ratingValue.toStringAsFixed(0),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 13.r,
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

/// Compact RetroAchievements indicator reused from the details footer.
class _CompactAchievementsIndicator extends StatelessWidget {
  final bool isLoading;
  final GameInfoAndUserProgress? gameInfo;
  final VoidCallback? onTap;

  const _CompactAchievementsIndicator({
    required this.isLoading,
    this.gameInfo,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final radii = Theme.of(context).extension<CornerRadii>() ?? CornerRadii.m();

    final noAchievements =
        !isLoading && (gameInfo == null || gameInfo!.numAchievements == 0);

    final awarded = gameInfo?.numAwardedToUser ?? 0;
    final total = gameInfo?.numAchievements ?? 0;
    final progress = total > 0 ? awarded / total : 0.0;

    final progressText = isLoading
        ? AppLocale.loading.getString(context)
        : (noAchievements
              ? AppLocale.noAchievements.getString(context)
              : '$awarded/$total');

    final theme = Theme.of(context);
    final statusColor = noAchievements
        ? theme.colorScheme.onSurface
        : Colors.orange;

    final gameIconUrl = gameInfo?.imageIcon.isNotEmpty == true
        ? 'https://media.retroachievements.org${gameInfo!.imageIcon}'
        : null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (onTap == null) return;
          SfxService().playNavSound();
          onTap!();
        },
        canRequestFocus: false,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
        borderRadius: radii.radiusInternal,
        child: Container(
          width: 101.r,
          height: 32.r,
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withValues(alpha: 0.9),
            borderRadius: radii.radiusExternal,
            border: Border.all(color: theme.colorScheme.outline, width: 1.r),
            boxShadow: [
              BoxShadow(
                color: theme.colorScheme.shadow.withValues(alpha: 0.1),
                blurRadius: 4.r,
                offset: Offset(2.0.r, 2.0.r),
              ),
            ],
          ),
          child: Padding(
            // Match the rating pill's 8.r horizontal inset so the trophy icon
            // doesn't hug the pill's left border (the pill's width above is
            // widened to 101.r to absorb the padding + the 6.r icon→text gap
            // without squeezing the 56.r text/progress column).
            padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 3.r),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: radii.radiusInternal,
                  child: Container(
                    width: 22.r,
                    height: 22.r,
                    color: theme.colorScheme.surface,
                    child: gameIconUrl != null
                        ? Image.network(
                            gameIconUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Symbols.emoji_events_rounded,
                              color: statusColor,
                              size: 12.r,
                            ),
                          )
                        : Icon(
                            Symbols.emoji_events_rounded,
                            color: statusColor,
                            size: 12.r,
                          ),
                  ),
                ),
                SizedBox(width: 6.r),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 56.r,
                      child: Text(
                        progressText.toUpperCase(),
                        style: TextStyle(
                          color: theme.colorScheme.onSurface,
                          fontSize: 8.r,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(height: 2.r),
                    // Bar is deliberately narrower than the 56.r text row so it
                    // doesn't run to the pill's right edge — leaves a right
                    // margin under the progress count.
                    SizedBox(
                      width: 46.r,
                      child: ClipRRect(
                        borderRadius: radii.radiusInternal,
                        child: LinearProgressIndicator(
                          value: isLoading ? null : progress,
                          minHeight: 3.5.r,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Select-tap hint + current sound state for the preview video, tappable for
/// touchscreen users. Watches the config provider on its own so the memoized
/// footer instance around it never has to rebuild when sound is toggled.
class _MuteHintPill extends StatelessWidget {
  final VoidCallback onToggleMute;

  const _MuteHintPill({required this.onToggleMute});

  @override
  Widget build(BuildContext context) {
    final radii = Theme.of(context).extension<CornerRadii>() ?? CornerRadii.m();
    final scheme = Theme.of(context).colorScheme;

    return Selector<SqliteConfigProvider, bool>(
      selector: (_, provider) => !provider.config.videoSound,
      builder: (context, isMuted, _) {
        return Material(
          color: scheme.surface.withValues(alpha: 0.9),
          borderRadius: radii.radiusExternal,
          child: InkWell(
            onTap: () {
              SfxService().playNavSound();
              onToggleMute();
            },
            canRequestFocus: false,
            borderRadius: radii.radiusExternal,
            child: Container(
              height: 32.r,
              padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 4.r),
              decoration: BoxDecoration(
                borderRadius: radii.radiusExternal,
                border: Border.all(color: scheme.outline, width: 1.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/gamepad/Xbox_View_button.png',
                    width: 15.r,
                    height: 15.r,
                    color: scheme.onSurface,
                  ),
                  SizedBox(width: 4.r),
                  Icon(
                    isMuted
                        ? Symbols.volume_off_rounded
                        : Symbols.volume_up_rounded,
                    size: 15.r,
                    color: scheme.onSurface,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
