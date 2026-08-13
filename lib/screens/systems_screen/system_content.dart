import 'dart:async';

import 'package:flutter/material.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:provider/provider.dart';
import 'package:neostation/providers/theme_provider.dart';
import 'package:neostation/widgets/splash_status_layout.dart';
import '../../../providers/sqlite_config_provider.dart';
import 'my_systems_section/my_systems_grid.dart';
import 'my_systems_section/initial_setup_widget.dart';

/// Orchestrator for the 'Systems' tab content.
///
/// Manages the visual state transition between the initial scanning/loading phase,
/// the setup wizard for first-time users, and the primary system library grid.
class SystemContent extends StatefulWidget {
  const SystemContent({super.key, this.selectedIndex = 0, this.onCardTapped});

  /// Index of the currently selected system card within the grid.
  final int selectedIndex;

  /// Callback invoked when a system card is interactively selected.
  final Function(int index)? onCardTapped;

  @override
  State<SystemContent> createState() => _SystemContentState();
}

class _SystemContentState extends State<SystemContent> {
  /// Minimum time the splash stays visible once shown. A fast scan (sub-second
  /// on a warm library) would otherwise blink the logo away before the shine
  /// animation is even perceptible.
  static const _minSplashDuration = Duration(milliseconds: 2500);

  /// When the splash first appeared; null once it has been released.
  DateTime? _splashShownAt;

  Timer? _releaseTimer;

  @override
  void dispose() {
    _releaseTimer?.cancel();
    super.dispose();
  }

  /// Returns whether the splash must stay up even though loading has finished,
  /// arming a one-shot timer that rebuilds when the minimum time is served.
  bool _holdSplash(bool isLoading) {
    if (isLoading) {
      _splashShownAt ??= DateTime.now();
      _releaseTimer?.cancel();
      _releaseTimer = null;
      return false;
    }
    final shownAt = _splashShownAt;
    if (shownAt == null) return false;

    final remaining = _minSplashDuration - DateTime.now().difference(shownAt);
    if (remaining <= Duration.zero) {
      _splashShownAt = null;
      return false;
    }
    _releaseTimer ??= Timer(remaining, () {
      if (mounted) setState(() => _splashShownAt = null);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<SqliteConfigProvider, ThemeProvider>(
      builder: (context, configProvider, themeProvider, child) {
        // Determine the current operational state of the library.
        final isLoading = configProvider.isLoading || configProvider.isScanning;
        final showSplash = isLoading || _holdSplash(isLoading);

        // Show setup wizard if scan is finished but no systems were resolved.
        final showInitialSetup =
            !showSplash &&
            !configProvider.hasDetectedSystems &&
            configProvider.scanCompleted;

        // Show primary library content only when initialization and scanning are complete.
        final showContent =
            !showSplash && configProvider.scanCompleted && !showInitialSetup;

        // PHASE 1: Loading and Initialization — a shimmering NeoStation logo
        // with a thin progress bar and the current scan step as quiet detail.
        // PHASE 2: First-Run Experience / Initial Setup.
        // PHASE 3: Primary System Library.
        final Widget phase;
        if (showSplash) {
          phase = KeyedSubtree(
            key: const ValueKey('splash'),
            child: _buildSplash(context, configProvider),
          );
        } else if (showInitialSetup) {
          phase = KeyedSubtree(
            key: const ValueKey('setup'),
            child: InitialSetupWidget(),
          );
        } else if (showContent) {
          phase = KeyedSubtree(
            key: const ValueKey('content'),
            child: MySystems(
              selectedIndex: widget.selectedIndex,
              onCardTapped: widget.onCardTapped,
            ),
          );
        } else {
          phase = const SizedBox.shrink(key: ValueKey('empty'));
        }

        // Cross-fade the splash into the library instead of a hard cut.
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 400),
          child: phase,
        );
      },
    );
  }

  Widget _buildSplash(
    BuildContext context,
    SqliteConfigProvider configProvider,
  ) {
    // The logo sits at the exact screen centre — the same spot it occupies on
    // the native splash and the startup screens — with the progress detail
    // hung below it, so nothing shifts across the whole intro sequence.
    return SplashStatusLayout(
      // Track the scan only once it is actually progressing. During the
      // waiting-for-storage phase progress sits at 0, which would park the
      // glint off-screen and leave the logo frozen for up to 30s — keep the
      // ambient sweep running until there's real movement.
      progress: configProvider.isScanning && configProvider.scanProgress > 0
          ? configProvider.scanProgress
          : null,
      children: [
        if (configProvider.isScanning) ...[
          SizedBox(
            width: 220,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: configProvider.scanProgress,
                minHeight: 3,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            configProvider.scanStatus.isNotEmpty
                ? configProvider.scanStatus
                : AppLocale.scanningSystemsRoms.getString(context),
            // 17 to match the startup screen's status line — the theme's
            // bodySmall (12) reads too small at couch distance.
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 17,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}
