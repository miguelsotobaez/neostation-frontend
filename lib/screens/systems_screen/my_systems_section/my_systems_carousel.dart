import 'dart:io';
import 'package:flutter/material.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/models/my_systems.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/screens/app_screen.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:provider/provider.dart';
import '../../../providers/sqlite_config_provider.dart';
import '../../../providers/sqlite_database_provider.dart';
import '../../../providers/file_provider.dart';
import '../../../themes/corner_radii.dart';
import '../../../utils/gamepad_nav.dart';
import '../../../services/game_service.dart';
import '../../../utils/game_launch_utils.dart';
import '../../../providers/system_background_provider.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/widgets/system_emulator_settings_dialog.dart';
import '../../game_screen/android_apps/android_apps_grid.dart';
import 'package:neostation/sync/sync_manager.dart';
import 'package:neostation/providers/neo_assets_provider.dart';
import 'package:neostation/providers/theme_provider.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/services/secondary_achievements_controller.dart';
import '../../game_screen/my_games_list.dart';
import 'package:neostation/models/secondary_display_state.dart';
import 'package:neostation/widgets/header_sort_dropdown.dart';
import 'package:neostation/widgets/native_carousel.dart';
import 'system_list_builder.dart';
import 'system_card.dart';

/// A premium carousel-based orchestrator for system and recent game selection.
///
/// Provides a high-immersion experience with dynamic backgrounds, music-synced
/// shaders, and optimized hardware navigation support.
class MySystemsCarousel extends StatefulWidget {
  const MySystemsCarousel({
    super.key,
    this.selectedIndex = 0,
    this.onCardTapped,
  });

  /// The initially selected system index.
  final int selectedIndex;

  /// Callback for system selection via interaction.
  final Function(int index)? onCardTapped;

  @override
  State<MySystemsCarousel> createState() => _MySystemsCarouselState();
}

class _MySystemsCarouselState extends State<MySystemsCarousel> {
  final GlobalKey<NativeCarouselState> _carouselKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();

  /// Active selection index within the carousel.
  int _currentIndex = 0;

  /// Fractional carousel page position, updated continuously while scrolling.
  /// Drives the bottom indicator cursor so it tracks the carousel image in
  /// lock-step instead of lagging until the page settles.
  final ValueNotifier<double> _pageOffsetNotifier = ValueNotifier(0.0);

  /// Hardware navigation manager for this specific view layer.
  late GamepadNavigation _gamepadNav;

  /// Set while game launch dialog is active to hide carousel content and free RAM.
  bool _isGameLaunching = false;

  // ── Pull-to-refresh (Android) ──────────────────────────────────────────
  static const double _maxPull = 75.0;
  final ValueNotifier<double> _pullOffsetNotifier = ValueNotifier(0.0);
  final ValueNotifier<double> _pullProgress = ValueNotifier(0.0);
  bool _pullReady = false;

  SecondaryDisplayState? _secondaryDisplayState;

  /// Drives the live RetroAchievements panel on the secondary display for games
  /// launched directly from the "Recent Games" cards.
  final SecondaryAchievementsController _achievementsController =
      SecondaryAchievementsController();

  /// Asset mapping caches for the active theme.
  final Map<String, String?> _themeBackgrounds = {};
  String _lastThemeFolder = '';
  final bool _loadingThemeAssets = false;

  /// Cache for computed TextPainter widths in the system indicator bar.
  final Map<String, double> _itemWidthCache = {};

  /// Tracks the last index for which _updateBackground was scheduled, to avoid
  /// firing redundant postFrameCallbacks on every build.
  int _lastBackgroundBuildIndex = -1;

  /// Cached systems list and indicator-label widths from the last build.
  /// The continuous scroll handler (fired every frame while swiping) reads
  /// these instead of rebuilding the list + re-measuring text every frame.
  List<SystemInfo>? _cachedSystems;
  List<double>? _cachedWidths;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.selectedIndex;
    _pageOffsetNotifier.value = _currentIndex.toDouble();
    _initializeGamepad();

    if (Platform.isAndroid) {
      _secondaryDisplayState = SecondaryDisplayState.instance;
      _secondaryDisplayState!.addListener(_onSecondaryStateChanged);
    }

    // Ensure state synchronization after first layout pass.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToIndex(_currentIndex);
      _loadThemeAssetsForSystems();
      // Explicitly check current shared state in case secondary was already
      // active before we subscribed (listener only fires on changes, not on
      // the initial value already present in SharedState).
      _onSecondaryStateChanged();
      // Also attempt direct update — works when secondary is already connected.
      _updateSecondaryScreenName();
    });
  }

  bool _prevIsSecondaryActive = false;
  // Tracks the scan-active state across builds so we can re-push the settled
  // selection to the secondary display exactly when the initial scan finishes.
  bool _wasScanning = false;

  // When secondary display signals it's active (startup or reconnect),
  // immediately push current system state so default logo never shows.
  void _onSecondaryStateChanged() {
    if (!mounted) return;
    final isActive = _secondaryDisplayState?.value?.isSecondaryActive ?? false;
    final wasActive = _prevIsSecondaryActive;
    // Update the guard BEFORE calling _updateSecondaryScreenName(): that call
    // writes secondary state synchronously, which re-enters this listener. If
    // the flag were still false on re-entry the guard would pass again, looping
    // until the stack overflows. Setting it first makes the re-entry a no-op.
    _prevIsSecondaryActive = isActive;
    if (isActive && !wasActive) {
      _updateSecondaryScreenName();
    }
  }

  @override
  void didUpdateWidget(MySystemsCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync external index changes with internal carousel state.
    if (widget.selectedIndex != oldWidget.selectedIndex &&
        widget.selectedIndex != _currentIndex) {
      setState(() {
        _currentIndex = widget.selectedIndex;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _carouselKey.currentState?.jumpToPage(_currentIndex);
      });
    }
  }

  @override
  void dispose() {
    // Shared singleton — detach our listener, never dispose the instance.
    _secondaryDisplayState?.removeListener(_onSecondaryStateChanged);
    _cleanupGamepad();
    _pageOffsetNotifier.dispose();
    _scrollController.dispose();
    _achievementsController.dispose();
    super.dispose();
  }

  /// Configures hardware navigation layers for the carousel.
  void _initializeGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateLeft: _navigatePrevious,
      onNavigateRight: _navigateNext,
      onSelectItem: _selectCurrentSystem,
      onSettings: _openSystemSettingsFromCarousel,
      onXButton: () {
        HeaderSortDropdown.globalKey.currentState?.showDropdown();
      },
      onPreviousTab: AppNavigation.previousTab,
      onNextTab: AppNavigation.nextTab,
      onLeftBumper: AppNavigation.previousTab,
      onRightBumper: AppNavigation.nextTab,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'my_systems_carousel',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });
  }

  void _cleanupGamepad() {
    GamepadNavigationManager.popLayer('my_systems_carousel');
    _gamepadNav.dispose();
  }

  /// Logic for smooth previous item navigation.
  void _navigatePrevious() {
    SfxService().playNavSound();
    _carouselKey.currentState?.previousPage();
  }

  void _navigateNext() {
    SfxService().playNavSound();
    _carouselKey.currentState?.nextPage();
  }

  /// Aggregates all logical systems (including virtuals like 'Recent') for display.
  List<SystemInfo> _getSystemsList() {
    final configProvider = Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    );
    final dbProvider = Provider.of<SqliteDatabaseProvider>(
      context,
      listen: false,
    );
    final fileProvider = Provider.of<FileProvider>(context, listen: false);
    return buildSystemsList(
      context: context,
      configProvider: configProvider,
      dbProvider: dbProvider,
      fileProvider: fileProvider,
    );
  }

  /// Executes navigation for the currently focused carousel item.
  void _selectCurrentSystem() {
    if (!mounted) return;

    final allSystems = _getSystemsList();
    final fileProvider = Provider.of<FileProvider>(context, listen: false);

    if (_currentIndex >= 0 && _currentIndex < allSystems.length) {
      _navigateToSystem(context, allSystems[_currentIndex], fileProvider);
    }
  }

  /// Orchestrates navigation to system-specific games lists or direct game launches.
  void _navigateToSystem(
    BuildContext context,
    SystemInfo systemInfo,
    FileProvider fileProvider,
  ) async {
    _gamepadNav.deactivate();

    final configProvider = Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    );

    // SCENARIO A: Direct Game Launch from 'Recent Games'.
    if (systemInfo.isGame && systemInfo.gameModel != null) {
      final gameSystemModel = configProvider.detectedSystems
          .cast<SystemModel?>()
          .firstWhere(
            (sys) => sys?.folderName == systemInfo.gameModel!.systemFolderName,
            orElse: () => null,
          );

      if (gameSystemModel == null) {
        if (mounted) {
          AppNotification.showNotification(
            context,
            AppLocale.errorSystemNotFound.getString(context),
            type: NotificationType.error,
          );
          _gamepadNav.activate();
        }
        return;
      }

      try {
        _gamepadNav.deactivate();
        setState(() => _isGameLaunching = true);

        // Free maximum RAM before handing off to the emulator.
        imageCache.clear();
        imageCache.clearLiveImages();
        if (context.mounted) {
          context.read<SystemBackgroundProvider>().clear();
        }

        final syncProvider = context.read<SyncManager>().active!;

        // Push the in-game RetroAchievements panel to the secondary display.
        // Fired without awaiting so it never blocks the emulator handoff; it
        // lands during launchGameWithDialog's foreground window, overlaying the
        // recent game's art until the game exits.
        final boxartPath = SecondaryAchievementsController.resolveBoxart(
          systemInfo.gameModel!,
          gameSystemModel.primaryFolderName,
          fileProvider,
        );
        // ignore: unawaited_futures
        _achievementsController.pushForLaunch(
          state: _secondaryDisplayState,
          provider: context.read<RetroAchievementsProvider>(),
          game: systemInfo.gameModel!,
          systemFolderName: gameSystemModel.primaryFolderName,
          boxartPath: boxartPath,
        );

        await launchGameWithDialog(
          context: context,
          game: systemInfo.gameModel!,
          system: gameSystemModel,
          fileProvider: fileProvider,
          syncProvider: syncProvider,
          onGameClosed: () {
            // Stop the poll and hide the panel so it fades back to the art.
            _achievementsController.stop(hidePanel: true);
            if (mounted) setState(() => _isGameLaunching = false);
            _gamepadNav.activate();
            Provider.of<SqliteDatabaseProvider>(
              context,
              listen: false,
            ).refresh();
          },
          onLaunchFailed: (ctx, r) async {
            _achievementsController.stop(hidePanel: true);
            if (mounted) setState(() => _isGameLaunching = false);
            _gamepadNav.activate();
          },
        );
      } catch (e) {
        if (context.mounted) {
          AppNotification.showNotification(
            context,
            AppLocale.errorLaunchingGame
                .getString(context)
                .replaceFirst('{error}', e.toString()),
            type: NotificationType.error,
          );
        }
        _gamepadNav.activate();
      }
      return;
    }

    // SCENARIO B: System Library Navigation.
    try {
      if (systemInfo.folderName == 'all') {
        final allGamesSystem = _createAllGamesSystem(
          configProvider.detectedSystems,
        );
        final targetScreen = SystemGamesList(
          system: allGamesSystem,
          fileProvider: fileProvider,
        );

        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => targetScreen),
        );
      } else if (systemInfo.folderName == 'android') {
        final systemMeta = configProvider.detectedSystems.firstWhere(
          (system) => system.folderName == 'android',
        );
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => AndroidAppsGrid(system: systemMeta),
          ),
        );
      } else {
        final systemMeta = configProvider.detectedSystems.firstWhere(
          (system) => system.folderName == systemInfo.folderName,
          orElse: () =>
              throw Exception('System not found: ${systemInfo.folderName}'),
        );
        final targetScreen = SystemGamesList(
          system: systemMeta,
          fileProvider: fileProvider,
        );
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => targetScreen),
        );
      }
    } finally {
      if (mounted) {
        _gamepadNav.activate();

        // Ensure secondary display is synchronized upon return.
        await _updateSecondaryScreenName();

        if (context.mounted) {
          Provider.of<SqliteDatabaseProvider>(context, listen: false).refresh();
        }
      }
    }
  }

  /// Opens configuration dialogs for the focused carousel item.
  void _openSystemSettingsFromCarousel() async {
    final allSystems = _getSystemsList();

    if (_currentIndex < 0 || _currentIndex >= allSystems.length) return;

    final selectedSystemInfo = allSystems[_currentIndex];

    // Block configuration for individual game cards (Recent Activity).
    if (selectedSystemInfo.isGame) {
      AppNotification.showNotification(
        context,
        AppLocale.settingsNotAvailableRecent.getString(context),
        type: NotificationType.info,
      );
      return;
    }

    final configProvider = Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    );

    final selectedSystem = selectedSystemInfo.folderName == 'all'
        ? _createAllGamesSystem(configProvider.detectedSystems)
        : configProvider.detectedSystems.cast<SystemModel?>().firstWhere(
            (system) => system?.folderName == selectedSystemInfo.folderName,
            orElse: () => null,
          );

    if (selectedSystem == null) return;

    if (mounted) {
      await showDialog(
        context: context,
        builder: (context) =>
            SystemEmulatorSettingsDialog(system: selectedSystem),
      );
    }
  }

  /// Internal utility to create the virtual 'All Games' model.
  SystemModel _createAllGamesSystem(List<dynamic> detectedSystems) {
    final existingAll = detectedSystems.cast<SystemModel?>().firstWhere(
      (s) => s?.folderName == 'all',
      orElse: () => null,
    );

    return SystemModel(
      id: 'all',
      folderName: 'all',
      realName:
          existingAll?.realName ?? AppLocale.allSystems.getString(context),
      iconImage: existingAll?.iconImage ?? '/images/icons/folder-bulk.png',
      color: existingAll?.color ?? '#ff006a',
      customBackgroundPath: existingAll?.customBackgroundPath,
      customLogoPath: existingAll?.customLogoPath,
      hideLogo: existingAll?.hideLogo ?? false,
      imageVersion: existingAll?.imageVersion ?? 0,
      romCount: detectedSystems.fold<int>(
        0,
        (sum, system) => sum + (system.romCount as num).toInt(),
      ),
      detected: true,
    );
  }

  /// Calculates the cumulative x-offset for a specific index in the horizontal scroll list.
  double _getItemOffset(int index, List<double> widths) {
    double offset = 0;
    for (int i = 0; i < index; i++) {
      offset += widths[i] + 4.r; // 4.r is the standard system card margin.
    }
    return offset;
  }

  /// Interpolated (left, width) for the sliding indicator cursor at a
  /// fractional carousel page, so the cursor tracks the carousel image
  /// continuously rather than jumping only once the page settles.
  (double, double) _cursorRect(double page, List<double> widths) {
    if (widths.isEmpty) return (0, 0);
    final maxIndex = widths.length - 1;
    final clampedPage = page.clamp(0.0, maxIndex.toDouble());
    final fromIndex = clampedPage.floor();
    final toIndex = clampedPage.ceil();
    final fraction = clampedPage - fromIndex;

    final fromOffset = _getItemOffset(fromIndex, widths);
    final toOffset = _getItemOffset(toIndex, widths);
    final left = fromOffset + (toOffset - fromOffset) * fraction;
    final width =
        widths[fromIndex] + (widths[toIndex] - widths[fromIndex]) * fraction;
    return (left, width);
  }

  /// Centrally aligns the selected item in the scrollable secondary indicator list.
  void _scrollToIndex(int index) {
    _scrollToPage(index.toDouble(), animate: true);
  }

  /// Aligns the bottom indicator bar to a fractional page position.
  ///
  /// [animate] should be false for the continuous per-frame updates driven by
  /// carousel scrolling — it uses [ScrollController.jumpTo] so the bar tracks
  /// the finger/animation in lock-step instead of chasing a fresh 200ms
  /// [ScrollController.animateTo] on every frame (which thrashes the ticker and
  /// drops frames). Discrete jumps (first layout, taps) pass animate: true.
  void _scrollToPage(double page, {bool animate = false}) {
    if (!_scrollController.hasClients) return;

    // Reuse the list + measured widths from the last build; only rebuild if the
    // cache hasn't been populated yet. Rebuilding here every frame ran DB
    // queries and TextPainter layout on the hot scroll path.
    final allSystems = _cachedSystems ?? _getSystemsList();
    final textStyle = TextStyle(fontSize: 10.r, fontWeight: FontWeight.bold);
    final widths =
        _cachedWidths ??
        allSystems.map((s) => _calculateItemWidth(s, textStyle)).toList();
    if (widths.isEmpty) return;
    final screenWidth = MediaQuery.of(context).size.width;

    final fromIndex = page.floor();
    final toIndex = page.ceil();
    final fraction = page - fromIndex;

    final fromOffset = _getItemOffset(fromIndex, widths);
    final toOffset = toIndex < widths.length
        ? _getItemOffset(toIndex, widths)
        : fromOffset;

    final itemWidth = widths[fromIndex.clamp(0, widths.length - 1)];
    final itemOffset = fromOffset + (toOffset - fromOffset) * fraction;
    final paddingOffset = 10.r;

    double offset =
        itemOffset - (screenWidth / 2) + (itemWidth / 2) + paddingOffset;

    offset = offset.clamp(0.0, _scrollController.position.maxScrollExtent);

    if (_scrollController.position.maxScrollExtent > 0) {
      if (animate) {
        _scrollController.animateTo(
          offset,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(offset);
      }
    }
  }

  /// Dynamically computes width for the system label indicator based on font metrics.
  /// Results are cached by text + font key to avoid repeated TextPainter layout calls.
  double _calculateItemWidth(SystemInfo system, TextStyle style) {
    final text = (system.shortName ?? system.title ?? "Unknown").toUpperCase();
    final cacheKey = '$text|${style.fontSize}|${style.fontWeight?.value}';
    return _itemWidthCache.putIfAbsent(cacheKey, () {
      final textPainter = TextPainter(
        text: TextSpan(text: text, style: style),
        textAlign: TextAlign.center,
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      return textPainter.width + 24.r;
    });
  }

  /// Synchronously loads theme-specific backgrounds and logos for the carousel library.
  void _loadThemeAssetsForSystems() {
    if (!mounted || _loadingThemeAssets) return;

    final neoAssets = context.read<NeoAssetsProvider>();
    final themeFolder = neoAssets.activeThemeFolder;

    if (themeFolder == _lastThemeFolder) return;
    _lastThemeFolder = themeFolder;

    if (themeFolder.isEmpty) {
      if (_themeBackgrounds.isNotEmpty) {
        setState(() {
          _themeBackgrounds.clear();
        });
      }
      return;
    }

    final systems = _getSystemsList();
    final folderNames = systems
        .where((s) => !s.isGame)
        .map((s) => s.primaryFolderName ?? s.folderName ?? '')
        .where((f) => f.isNotEmpty)
        .toSet();

    final Map<String, String?> newBgs = {};

    for (final folder in folderNames) {
      newBgs[folder] = neoAssets.getBackgroundForSystemSync(folder);
    }

    setState(() {
      _themeBackgrounds
        ..clear()
        ..addAll(newBgs);
      _itemWidthCache.clear();
    });
  }

  /// Logic to update the global system background provider on selection change.
  void _updateBackground(SystemInfo system) {
    if (!mounted) return;

    final displayFolderName = system.primaryFolderName;
    final customBgPath = system.customBackgroundPath;
    final hasCustomBg = customBgPath != null && customBgPath.isNotEmpty;
    final ImageProvider imageProvider;
    final String imageKey;

    if (hasCustomBg) {
      imageProvider = FileImage(File(customBgPath));
      imageKey = customBgPath;
    } else {
      final themeBgPath = _themeBackgrounds[displayFolderName ?? ''];
      if (themeBgPath != null && themeBgPath.isNotEmpty) {
        imageProvider = FileImage(File(themeBgPath));
        imageKey = themeBgPath;
      } else {
        final path =
            'assets/images/systems/grid/$displayFolderName-background.webp';
        imageProvider = AssetImage(path);
        imageKey = path;
      }
    }

    context.read<SystemBackgroundProvider>().updateImage(
      imageProvider,
      imagePath: imageKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isGameLaunching) {
      return const PopScope(canPop: false, child: SizedBox.shrink());
    }

    // Reload theme assets when active theme changes
    final neoThemeFolder = context.select<NeoAssetsProvider, String>(
      (p) => p.activeThemeFolder,
    );
    final isScanning = context.select<SqliteConfigProvider, bool>(
      (p) => p.isScanning,
    );
    if (neoThemeFolder != _lastThemeFolder) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadThemeAssetsForSystems();
        // Theme assets (and thus _themeBackgrounds) have only just resolved.
        // Re-push the current selection so the secondary display picks up the
        // now-available background — otherwise the initially-settled system
        // (e.g. the 'All' virtual system) stays blank on the secondary until
        // the user navigates and triggers a push via onPageChanged.
        // Skip while scanning so the background doesn't pop in over the scan
        // display; the scan-settle branch below re-pushes once the scan ends.
        if (!isScanning) _updateSecondaryScreenName();
      });
    }
    // When the initial scan settles, re-push the settled selection so the
    // secondary display reveals its background at the same moment the primary
    // screen settles — not partway through the scan.
    if (_wasScanning && !isScanning) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadThemeAssetsForSystems();
        _updateSecondaryScreenName();
      });
    }
    _wasScanning = isScanning;

    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      child: Selector2<SqliteConfigProvider, SqliteDatabaseProvider, int>(
        selector: (_, config, db) => Object.hash(
          config.detectedSystems.length,
          config.hiddenSystemFolders.length,
          config.totalGames,
          config.config.hideRecentCard,
          db.getRecentlyPlayedGames(1).firstOrNull?.romPath.hashCode,
          db.totalFavorites,
        ),
        builder: (context, _, child) {
          final allSystems = _getSystemsList();

          if (allSystems.isEmpty) {
            return Center(
              child: Text(
                AppLocale.noSystemsFound.getString(context),
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontSize: 20.r,
                ),
              ),
            );
          }

          // Trigger background update only when the displayed index changes.
          if (_lastBackgroundBuildIndex != _currentIndex) {
            _lastBackgroundBuildIndex = _currentIndex;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _updateBackground(allSystems[_currentIndex]);
              }
            });
          }

          final textStyle = TextStyle(
            color: theme.colorScheme.onSurface,
            fontSize: 10.r,
            fontWeight: FontWeight.normal,
          );
          final selectedTextStyle = textStyle.copyWith(
            color: theme.colorScheme.onPrimary,
            fontWeight: FontWeight.bold,
          );

          final widths = allSystems
              .map((s) => _calculateItemWidth(s, selectedTextStyle))
              .toList();

          // Cache for the hot scroll path (_scrollToPage) so it doesn't rebuild
          // the list or re-measure text on every frame while scrolling.
          _cachedSystems = allSystems;
          _cachedWidths = widths;

          Widget content = Column(
            children: [
              // Primary Horizontal Carousel.
              Expanded(
                child: GestureDetector(
                  onVerticalDragStart: (_) {
                    _pullOffsetNotifier.value = 0.0;
                    _pullProgress.value = 0.0;
                    _pullReady = false;
                  },
                  onVerticalDragUpdate: (details) {
                    final deltaY = details.delta.dy;
                    if (deltaY > 0) {
                      final newOffset = (_pullOffsetNotifier.value + deltaY)
                          .clamp(0.0, _maxPull);
                      _pullOffsetNotifier.value = newOffset;
                      _pullProgress.value = (newOffset / _maxPull).clamp(
                        0.0,
                        1.0,
                      );
                      if (_pullProgress.value >= 1.0) _pullReady = true;
                    }
                  },
                  onVerticalDragEnd: (_) {
                    if (_pullReady) {
                      _pullReady = false;
                      _triggerRefresh();
                    }
                    _pullOffsetNotifier.value = 0.0;
                    _pullProgress.value = 0.0;
                  },
                  onVerticalDragCancel: () {
                    _pullReady = false;
                    _pullOffsetNotifier.value = 0.0;
                    _pullProgress.value = 0.0;
                  },
                  behavior: HitTestBehavior.translucent,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _pullOffsetNotifier,
                    builder: (context, offset, child) {
                      return Transform.translate(
                        offset: Offset(0, offset),
                        child: child!,
                      );
                    },
                    child: Focus(
                      descendantsAreFocusable:
                          false, // Intercept native Flutter focus to use custom gamepad logic.
                      skipTraversal: true,
                      child: RepaintBoundary(
                        child: NativeCarousel(
                          key: _carouselKey,
                          itemCount: allSystems.length,
                          initialIndex: _currentIndex,
                          footerHeight: 60.r,
                          // System cards are height-bound (square art + footer)
                          // so ~3.6 of them fit across the screen. With the
                          // default envelope the 4th card is already down to
                          // 44% scale / 10% opacity by the time it reaches the
                          // edge, leaving a ~16px sliver. Floor the scale, lift
                          // the fade, and pull the outer pair back toward the
                          // pack so the row visibly continues past both edges.
                          depth: const CarouselDepth(
                            minScale: 0.7,
                            opacityBase: 0.75,
                            opacityFalloff: 0.55,
                            minOpacity: 0.3,
                            edgePull: 0.15,
                          ),
                          itemBuilder: (context, index) {
                            final system = allSystems[index];
                            final isSelected = index == _currentIndex;
                            return SystemCard(
                              key: ValueKey(
                                'carousel_system_card_${system.title}_$index',
                              ),
                              info: system,
                              isSelected: isSelected,
                              backgroundCacheWidth: 1024,
                              onTap: () {
                                // Tapping an off-centre card brings it to the
                                // middle; tapping the centred one enters it, so
                                // touch users never need the footer's A button.
                                // (SystemCard plays the sound.)
                                if (isSelected) {
                                  _selectCurrentSystem();
                                } else {
                                  _carouselKey.currentState?.animateToPage(
                                    index,
                                  );
                                }
                              },
                            );
                          },
                          onPageScrolled: (page) {
                            _pageOffsetNotifier.value = page;
                            _scrollToPage(page);
                          },
                          onPageChanged: (index, reason) {
                            if (reason == CarouselPageChangeReason.manual) {
                              SfxService().playNavSound();
                            }
                            setState(() {
                              _currentIndex = index;
                            });
                            _updateBackground(allSystems[index]);
                            _updateSecondaryScreenName();
                            widget.onCardTapped?.call(index);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Secondary Systems Indicator List (Bottom).
              SizedBox(
                height: 40.r,
                child: SingleChildScrollView(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.symmetric(vertical: 6.r, horizontal: 4.r),
                  child: Stack(
                    children: [
                      // Background track: every label keeps its surface shape
                      // so unselected items still look like buttons.
                      Row(
                        children: allSystems.asMap().entries.map((entry) {
                          final itemWidth = widths[entry.key];
                          return Container(
                            width: itemWidth,
                            height: 32.r,
                            margin: EdgeInsets.only(right: 4.r),
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.surface,
                              borderRadius:
                                  Theme.of(
                                    context,
                                  ).extension<CornerRadii>()?.radiusExternal ??
                                  BorderRadius.circular(14.r),
                            ),
                          );
                        }).toList(),
                      ),

                      // Focused item sliding indicator. Painted between the
                      // backgrounds and the text so the selected label gets a
                      // solid fill while the text stays perfectly readable.
                      Positioned.fill(
                        child: ValueListenableBuilder<double>(
                          valueListenable: _pageOffsetNotifier,
                          builder: (context, page, _) {
                            final (left, width) = _cursorRect(page, widths);
                            return Stack(
                              children: [
                                Positioned(
                                  left: left,
                                  top: 0,
                                  bottom: 0,
                                  width: width,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary,
                                      borderRadius:
                                          Theme.of(context)
                                              .extension<CornerRadii>()
                                              ?.radiusExternal ??
                                          BorderRadius.circular(14.r),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ),

                      // Foreground text track. Transparent background so the
                      // selector and surface backgrounds show through, while
                      // the selected label uses onPrimary for contrast.
                      ValueListenableBuilder<double>(
                        valueListenable: _pageOffsetNotifier,
                        builder: (context, page, _) {
                          final selectedIndex = page.round().clamp(
                            0,
                            allSystems.length - 1,
                          );
                          return Row(
                            children: allSystems.asMap().entries.map((entry) {
                              final index = entry.key;
                              final system = entry.value;
                              final isSelected = index == selectedIndex;
                              final itemWidth = widths[index];

                              return GestureDetector(
                                onTap: () {
                                  SfxService().playNavSound();
                                  _carouselKey.currentState?.animateToPage(
                                    index,
                                  );
                                },
                                child: Container(
                                  width: itemWidth,
                                  height: 32.r,
                                  margin: EdgeInsets.only(right: 4.r),
                                  alignment: Alignment.center,
                                  color: Colors.transparent,
                                  child: Text(
                                    (system.shortName ??
                                            system.title ??
                                            AppLocale.unknown.getString(
                                              context,
                                            ))
                                        .toUpperCase(),
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: isSelected
                                        ? selectedTextStyle
                                        : textStyle,
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );

          if (Platform.isAndroid) {
            content = Stack(
              children: [
                content,
                ValueListenableBuilder<double>(
                  valueListenable: _pullProgress,
                  builder: (context, progress, child) {
                    return AnimatedOpacity(
                      opacity: progress > 0 ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 150),
                      child: IgnorePointer(
                        child: Container(
                          alignment: Alignment.topCenter,
                          padding: EdgeInsets.only(top: 16.r),
                          child: SizedBox(
                            width: 32.r,
                            height: 32.r,
                            child: CircularProgressIndicator(
                              value: progress >= 1.0 ? null : progress,
                              strokeWidth: 3,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          }

          return content;
        },
      ),
    );
  }

  /// Pushes carousel state updates to secondary hardware displays (OEM support).
  Future<void> _updateSecondaryScreenName() async {
    if (!Platform.isAndroid) return;
    if (_secondaryDisplayState == null) return;

    final allSystems = _getSystemsList();
    if (_currentIndex >= 0 && _currentIndex < allSystems.length) {
      final system = allSystems[_currentIndex];
      final systemName = (system.shortName ?? system.title ?? "NEOSTATION")
          .toUpperCase();

      final folder = system.primaryFolderName ?? system.folderName ?? 'all';

      // Logo resolution for secondary display.
      final String? customLogo = system.customLogoPath?.isNotEmpty == true
          ? system.customLogoPath
          : null;
      final String? systemLogo = system.isGame
          ? system.customWheelImage
          : (customLogo ?? 'assets/images/logos/$folder.webp');
      final bool isLogoAsset = !system.isGame && customLogo == null;

      // Background resolution for secondary display.
      final String? customBg = system.customBackgroundPath;
      final bool hasCustomBg = customBg != null && customBg.isNotEmpty;
      final String? themeBg = hasCustomBg ? null : _themeBackgrounds[folder];
      final String? systemBackground = hasCustomBg ? customBg : themeBg;
      final bool isBackgroundAsset = false;

      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      final isOled = themeProvider.isOled;

      _secondaryDisplayState?.updateState(
        systemName: systemName,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor.toARGB32(),
        systemLogo: systemLogo,
        isLogoAsset: isLogoAsset,
        systemBackground: systemBackground,
        clearSystemBackground: systemBackground == null,
        isBackgroundAsset: isBackgroundAsset,
        useShader: systemBackground == null,
        shaderColor1: system.color1AsColor?.toARGB32(),
        shaderColor2: system.color2AsColor?.toARGB32(),
        isGameSelected: false,
        clearFanart: true,
        clearScreenshot: true,
        clearWheel: true,
        clearVideo: true,
        clearImageBytes: true,
        clearGameId: true,
        useFluidShader: false,
        isOled: isOled,
      );
    }
  }

  void _triggerRefresh() {
    final configProvider = context.read<SqliteConfigProvider>();
    if (!configProvider.isScanning) {
      SfxService().playNavSound();
      configProvider.scanSystems();
    }
  }
}
