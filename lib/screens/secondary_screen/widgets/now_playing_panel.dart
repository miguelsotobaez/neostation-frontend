import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../models/secondary_display_state.dart';
import '../now_playing_helpers.dart';
import 'app_dock.dart';

/// The Now Playing page shown on the secondary display: boxart + game/system
/// title + play-time / session / last-played stats, the app dock, and the
/// all-apps launcher button.
///
/// Pure, input-driven subtree — the owning [SecondaryScreen] passes the current
/// state snapshot, the live session readout ([sessionRunning] / [sessionTime]),
/// and the action callbacks, so the panel re-reads no state of its own.
class NowPlayingPanel extends StatelessWidget {
  const NowPlayingPanel({
    super.key,
    required this.value,
    required this.sessionRunning,
    required this.sessionTime,
    required this.onRequestScreenshot,
    required this.onLaunchApp,
    required this.onPickSlot,
    required this.onClearSlot,
    required this.onOpenLauncher,
    required this.onOpenAccessibilitySettings,
  });

  final SecondaryDisplayStateData value;

  /// Whether a play session is currently being timed (drives the SESSION stat).
  final bool sessionRunning;

  /// Pre-formatted elapsed session time (`HH:MM:SS`); only shown when
  /// [sessionRunning].
  final String sessionTime;

  /// Asks the main engine to capture a screenshot of the main screen.
  final VoidCallback onRequestScreenshot;

  /// Launches the docked app in `package` (prefers the bottom display).
  final void Function(String package) onLaunchApp;

  /// Opens the app picker to assign an app to the empty slot `index`.
  final void Function(int index) onPickSlot;

  /// Clears the app assigned to slot `index`.
  final void Function(int index) onClearSlot;

  /// Opens the app picker in launch mode (all-apps launcher).
  final VoidCallback onOpenLauncher;

  /// Opens Android accessibility settings to enable the Screen Return service.
  final VoidCallback onOpenAccessibilitySettings;

  @override
  Widget build(BuildContext context) {
    final title = (value.gameTitle != null && value.gameTitle!.isNotEmpty)
        ? value.gameTitle!
        : value.systemName;
    final scheme = panelScheme(value);

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: scheme.surface,
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(44.r, 32.r, 44.r, 96.r),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                buildNowPlayingBoxart(value.gameBoxart),
                SizedBox(width: 32.r),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'NOW PLAYING',
                        style: TextStyle(
                          color: scheme.primary,
                          fontSize: 14.r,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 3.r,
                        ),
                      ),
                      SizedBox(height: 12.r),
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 30.r,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8.r),
                      Text(
                        value.systemName.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.7),
                          fontSize: 16.r,
                          letterSpacing: 1.5.r,
                        ),
                      ),
                      SizedBox(height: 26.r),
                      buildNowPlayingStat(
                        scheme: scheme,
                        icon: Symbols.schedule_rounded,
                        label: 'PLAY TIME',
                        text: formatPlayTime(value.playTimeSeconds),
                      ),
                      if (sessionRunning) ...[
                        SizedBox(height: 12.r),
                        buildNowPlayingStat(
                          scheme: scheme,
                          icon: Symbols.timer_rounded,
                          label: 'SESSION',
                          text: sessionTime,
                        ),
                      ],
                      SizedBox(height: 12.r),
                      buildNowPlayingStat(
                        scheme: scheme,
                        icon: Symbols.history_rounded,
                        label: 'LAST PLAYED',
                        text: formatLastPlayed(value.lastPlayedMillis),
                      ),
                      if (value.screenshotAccessEnabled) ...[
                        SizedBox(height: 28.r),
                        _buildScreenshotButton(scheme),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: AppDock(
              value: value,
              onLaunchApp: onLaunchApp,
              onPickSlot: onPickSlot,
              onClearSlot: onClearSlot,
            ),
          ),
          // All-apps launcher pinned to the bottom-left corner.
          if (value.dockEnabled)
            Positioned(
              left: 16.r,
              bottom: 16.r,
              child: _buildLauncherButton(value),
            ),
        ],
      ),
    );
  }

  /// Tappable pill that asks the main engine to capture a system screenshot of
  /// the main screen.
  Widget _buildScreenshotButton(ColorScheme scheme) {
    return GestureDetector(
      onTap: onRequestScreenshot,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20.r, vertical: 12.r),
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.photo_camera_rounded,
              color: scheme.onSurface,
              size: 22.r,
            ),
            SizedBox(width: 12.r),
            Text(
              'SCREENSHOT',
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 14.r,
                fontWeight: FontWeight.w600,
                letterSpacing: 2.r,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The all-apps launcher, pinned to the bottom-left of the Now Playing
  /// screen. Normally opens the app picker in launch mode. When the Screen
  /// Return accessibility service isn't enabled, it's highlighted with an
  /// accent border + warning badge and instead opens accessibility settings —
  /// launching an app without that service would strand the user with no way
  /// back to Now Playing.
  Widget _buildLauncherButton(SecondaryDisplayStateData value) {
    final scheme = panelScheme(value);
    final accessOk = value.screenshotAccessEnabled;
    return GestureDetector(
      onTap: accessOk ? onOpenLauncher : onOpenAccessibilitySettings,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 56.r,
            height: 56.r,
            decoration: BoxDecoration(
              color: accessOk
                  ? scheme.onSurface.withValues(alpha: 0.05)
                  : scheme.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(
                color: accessOk
                    ? scheme.onSurface.withValues(alpha: 0.14)
                    : scheme.primary,
                width: accessOk ? 1.r : 2.r,
              ),
            ),
            child: Icon(
              Symbols.apps_rounded,
              color: accessOk
                  ? scheme.onSurface.withValues(alpha: 0.65)
                  : scheme.primary,
              size: 28.r,
            ),
          ),
          if (!accessOk)
            Positioned(
              top: -4.r,
              right: -4.r,
              child: Container(
                width: 20.r,
                height: 20.r,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.surface, width: 2.r),
                ),
                child: Icon(
                  Symbols.priority_high_rounded,
                  size: 12.r,
                  color: scheme.onPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
