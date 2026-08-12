import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/responsive.dart';
import 'package:neostation/models/my_systems.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/screens/app_screen.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:provider/provider.dart';
import '../../../themes/corner_radii.dart';
import '../../../utils/gamepad_nav.dart';
import '../../../services/game_service.dart';
import '../../../utils/game_launch_utils.dart';
import 'system_card.dart';
import '../../../providers/sqlite_config_provider.dart';
import '../../../providers/sqlite_database_provider.dart';
import '../../../providers/file_provider.dart';
import '../../../widgets/system_scan_progress_widget.dart';
import '../../game_screen/my_games_list.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'grid_geometry.dart';
import 'widgets/grid_loading_state.dart';
import 'widgets/grid_empty_state.dart';
import 'my_systems_carousel.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/widgets/system_emulator_settings_dialog.dart';
import 'package:neostation/sync/sync_manager.dart';
import 'package:neostation/providers/theme_provider.dart';
import '../../game_screen/android_apps/android_apps_grid.dart';
import 'package:neostation/widgets/header_sort_dropdown.dart';
import 'package:neostation/widgets/systems_grid_footer.dart';

import 'package:neostation/services/logger_service.dart';
import 'package:neostation/models/secondary_display_state.dart';
import 'package:neostation/providers/neo_assets_provider.dart';
import 'package:neostation/providers/system_background_provider.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/services/secondary_achievements_controller.dart';
import 'system_list_builder.dart';

part 'my_systems_grid/gamepad_grid_nav.dart';
part 'my_systems_grid/theme_background.dart';
part 'my_systems_grid/pull_to_refresh.dart';

/// Primary widget for the 'My Systems' view, supporting both Grid and Carousel layouts.
///
/// Orchestrates the selection and navigation of gaming systems, including handling
/// of 'Recent Games', 'Android Apps', and logical collections like 'All Games'.
class MySystems extends StatelessWidget {
  const MySystems({super.key, this.selectedIndex = 0, this.onCardTapped});

  static final _log = LoggerService.instance;

  /// Static lock to prevent race conditions during heavy navigation transitions.
  static bool isNavigating = false;

  /// Notifier to hide the systems grid while a game launch dialog is active.
  static final gridLaunchNotifier = ValueNotifier<bool>(false);

  /// Currently selected system index in the active layout (Grid or Carousel).
  final int selectedIndex;

  /// Callback for system selection via pointer interaction.
  final Function(int index)? onCardTapped;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          false, // Maintain application flow by preventing raw hardware back navigation.
      child: Consumer2<SqliteConfigProvider, SqliteDatabaseProvider>(
        builder: (context, configProvider, dbProvider, child) {
          // PHASE 1: Blocking Initialization.
          // If a high-priority system scan is active (e.g., first run), show a blocking status.
          if (configProvider.isGlobalScanning) {
            return const GridLoadingState();
          }

          // PHASE 2: Empty Library State.
          if (!configProvider.hasDetectedSystems) {
            return GridEmptyState(configProvider: configProvider);
          }

          // PHASE 3: Content Presentation.
          // Dynamically toggle between Carousel and Grid layouts based on user preference.
          final Widget systemsWidget;
          if (configProvider.config.systemViewMode == 'carousel') {
            final allSystems = _buildAllSystems(context, configProvider);
            final currentSystem = selectedIndex < allSystems.length
                ? allSystems[selectedIndex]
                : allSystems[0];

            systemsWidget = Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(top: 42.r),
                    child: MySystemsCarousel(
                      selectedIndex: selectedIndex,
                      onCardTapped: onCardTapped,
                    ),
                  ),
                ),
                SystemsGridFooter(
                  system: currentSystem,
                  onEnter: () {
                    SfxService().playEnterSound();
                    _navigateToSystem(context, currentSystem, configProvider);
                  },
                  onSettings: () {
                    SfxService().playEnterSound();
                    _openSystemSettings(context, currentSystem, configProvider);
                  },
                ),
              ],
            );
          } else {
            systemsWidget = _buildSystemsGrid(context, configProvider);
          }

          // If a non-blocking background scan is active, overlay a progress toast.
          if (configProvider.isScanning) {
            return Column(
              children: [
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: SystemScanProgressWidget(),
                ),
                Expanded(child: systemsWidget),
              ],
            );
          }

          return systemsWidget;
        },
      ),
    );
  }

  /// Aggregates all logical systems (recent games + detected systems) into a unified list.
  List<SystemInfo> _buildAllSystems(
    BuildContext context,
    SqliteConfigProvider configProvider,
  ) {
    final fileProvider = Provider.of<FileProvider>(context, listen: false);
    final dbProvider = Provider.of<SqliteDatabaseProvider>(context);
    return buildSystemsList(
      context: context,
      configProvider: configProvider,
      dbProvider: dbProvider,
      fileProvider: fileProvider,
    );
  }

  /// Builds the high-density grid layout for system selection.
  Widget _buildSystemsGrid(
    BuildContext context,
    SqliteConfigProvider configProvider,
  ) {
    final allSystems = _buildAllSystems(context, configProvider);

    // Bound check the selected index for safety.
    final currentSystem = selectedIndex < allSystems.length
        ? allSystems[selectedIndex]
        : allSystems[0];

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              left: 6.0.r,
              right: 6.0.r,
              top: 46.r,
              bottom: 0.r,
            ),
            child: SystemCardGridView(
              crossAxisCount: Responsive.getSystemsCrossAxisCountFromSize(
                configProvider.config.systemGridColumns,
              ),
              childAspectRatio: 0.80,
              selectedIndex: selectedIndex,
              onCardTapped: onCardTapped,
              systems: allSystems,
              onEnterPressed: () {
                final current = selectedIndex < allSystems.length
                    ? allSystems[selectedIndex]
                    : allSystems[0];
                _navigateToSystem(context, current, configProvider);
              },
              onEscapePressed: () {
                final current = selectedIndex < allSystems.length
                    ? allSystems[selectedIndex]
                    : allSystems[0];
                _openSystemSettings(context, current, configProvider);
              },
            ),
          ),
        ),
        // Sticky footer displaying active system metadata and secondary actions.
        SystemsGridFooter(
          system: currentSystem,
          onEnter: () {
            SfxService().playEnterSound();
            _navigateToSystem(context, currentSystem, configProvider);
          },
          onSettings: () {
            SfxService().playEnterSound();
            _openSystemSettings(context, currentSystem, configProvider);
          },
        ),
      ],
    );
  }

  /// Opens the emulator configuration dialog for a specific system.
  void _openSystemSettings(
    BuildContext context,
    SystemInfo system,
    SqliteConfigProvider configProvider,
  ) async {
    if (MySystems.isNavigating) return;
    MySystems.isNavigating = true;

    try {
      final selectedSystem = system.folderName == 'all'
          ? _createAllGamesSystem(context, configProvider.detectedSystems)
          : configProvider.detectedSystems.firstWhere(
              (s) => s.folderName == system.folderName,
            );

      await Future.delayed(const Duration(milliseconds: 50));

      if (context.mounted) {
        await showDialog(
          context: context,
          builder: (context) =>
              SystemEmulatorSettingsDialog(system: selectedSystem),
        );
      }

      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      if (context.mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.systemSettingsNotAvailable.getString(context),
          type: NotificationType.info,
        );
      }
    } finally {
      MySystems.isNavigating = false;
    }
  }

  /// Orchestrates navigation to a system games list or direct game launch.
  void _navigateToSystem(
    BuildContext context,
    SystemInfo systemInfo,
    SqliteConfigProvider configProvider,
  ) async {
    if (MySystems.isNavigating) return;
    MySystems.isNavigating = true;

    // SCENARIO A: Direct Game Launch (from Recent Games card).
    if (systemInfo.isGame && systemInfo.gameModel != null) {
      final gameSystemModel = configProvider.detectedSystems
          .cast<SystemModel?>()
          .firstWhere(
            (sys) => sys?.folderName == systemInfo.gameModel!.systemFolderName,
            orElse: () => null,
          );

      if (gameSystemModel == null) {
        if (context.mounted) {
          AppNotification.showNotification(
            context,
            AppLocale.errorSystemNotFound.getString(context),
            type: NotificationType.error,
          );
        }
        MySystems.isNavigating = false;
        return;
      }

      try {
        GamepadNavigationManager.deactivateAll();
        MySystems.gridLaunchNotifier.value = true;

        final fileProvider = Provider.of<FileProvider>(context, listen: false);
        final syncProvider = context.read<SyncManager>().active!;

        // Free maximum RAM before handing off to the emulator.
        imageCache.clear();
        imageCache.clearLiveImages();
        if (context.mounted) {
          context.read<SystemBackgroundProvider>().clear();
        }

        // Drive the in-game RetroAchievements panel on the secondary display.
        // This launch path lives on the stateless [MySystems] widget, so the
        // controller is scoped to this session: the periodic poll keeps itself
        // alive via the event loop, and the onGameClosed/onLaunchFailed
        // callbacks stop it. The app-lifetime shared state lives on the config
        // provider (the grid/footer have no per-widget instance of their own).
        final achievementsController = SecondaryAchievementsController();
        // ignore: unawaited_futures
        achievementsController.pushForLaunch(
          state: configProvider.secondaryDisplayState,
          provider: context.read<RetroAchievementsProvider>(),
          game: systemInfo.gameModel!,
          systemFolderName: gameSystemModel.primaryFolderName,
          boxartPath: SecondaryAchievementsController.resolveBoxart(
            systemInfo.gameModel!,
            gameSystemModel.primaryFolderName,
            fileProvider,
          ),
        );

        await launchGameWithDialog(
          context: context,
          game: systemInfo.gameModel!,
          system: gameSystemModel,
          fileProvider: fileProvider,
          syncProvider: syncProvider,
          onGameClosed: () {
            // Stop the poll and hide the panel so it fades back to the art.
            achievementsController.stop(hidePanel: true);
            MySystems.gridLaunchNotifier.value = false;
            GamepadNavigationManager.reactivate();
            Provider.of<SqliteDatabaseProvider>(
              context,
              listen: false,
            ).refresh();
          },
          onLaunchFailed: (ctx, r) async {
            achievementsController.stop(hidePanel: true);
            MySystems.gridLaunchNotifier.value = false;
            GamepadNavigationManager.reactivate();
          },
        );
      } catch (e) {
        MySystems.gridLaunchNotifier.value = false;
        if (context.mounted) {
          AppNotification.showNotification(
            context,
            AppLocale.errorLaunchingGame
                .getString(context)
                .replaceFirst('{error}', e.toString()),
            type: NotificationType.error,
          );
        }
        GamepadNavigationManager.reactivate();
      } finally {
        MySystems.isNavigating = false;
      }
      return;
    }

    // SCENARIO B: System Library Navigation.
    final fileProvider = Provider.of<FileProvider>(context, listen: false);
    GamepadNavigationManager.deactivateAll();

    try {
      if (systemInfo.folderName == 'all') {
        final allGamesSystem = _createAllGamesSystem(
          context,
          configProvider.detectedSystems,
        );
        final targetScreen = SystemGamesList(
          system: allGamesSystem,
          fileProvider: fileProvider,
        );

        if (context.mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => targetScreen),
          );
        }
      } else if (systemInfo.folderName == 'android') {
        final systemMeta = configProvider.detectedSystems.firstWhere(
          (system) => system.folderName == 'android',
        );
        if (context.mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AndroidAppsGrid(system: systemMeta),
            ),
          );
        }
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

        if (context.mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => targetScreen),
          );
        }
      }
    } catch (e) {
      _log.e('MySystems: Navigation lifecycle error', error: e);
    } finally {
      MySystems.isNavigating = false;
      GamepadNavigationManager.reactivate();

      // Ensure the secondary display is synchronized with the current system state upon return.
      if (context.mounted) {
        await _updateSecondaryScreenForSystem(context, systemInfo);
      }

      if (context.mounted) {
        Provider.of<SqliteDatabaseProvider>(context, listen: false).refresh();
      }
    }
  }

  /// Synchronizes metadata and visual assets with external display hardware.
  static Future<void> _updateSecondaryScreenForSystem(
    BuildContext context,
    SystemInfo system,
  ) async {
    if (!Platform.isAndroid) return;

    final secondaryState = Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    ).secondaryDisplayState;
    if (secondaryState == null) return;
    final folder = system.primaryFolderName ?? system.folderName ?? 'all';

    final neoAssets = Provider.of<NeoAssetsProvider>(context, listen: false);

    final String? customLogo = system.customLogoPath?.isNotEmpty == true
        ? system.customLogoPath
        : null;
    final String? systemLogo = system.isGame
        ? system.customWheelImage
        : (customLogo ?? 'assets/images/logos/$folder.webp');
    final bool isLogoAsset = !system.isGame && customLogo == null;

    final String? customBg = system.customBackgroundPath;
    final bool hasCustomBg = customBg != null && customBg.isNotEmpty;
    final String? themeBg = hasCustomBg
        ? null
        : neoAssets.getBackgroundForSystemSync(folder);
    final String? systemBackground = hasCustomBg ? customBg : themeBg;
    final bool isBackgroundAsset = false;

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isOled = themeProvider.isOled;

    secondaryState.updateState(
      systemName: system.title ?? "NEOSTATION",
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

/// Creates a virtual 'All Games' system model by aggregating metadata from all detected systems.
SystemModel _createAllGamesSystem(
  BuildContext context,
  List<dynamic> detectedSystems,
) {
  // Resolve settings from an existing 'all' entry if available in persistence.
  final existingAll = detectedSystems.cast<SystemModel?>().firstWhere(
    (s) => s?.folderName == 'all',
    orElse: () => null,
  );

  return SystemModel(
    id: 'all',
    folderName: 'all',
    realName: existingAll?.realName ?? AppLocale.allSystems.getString(context),
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

/// A stateful grid view optimized for system selection with mixed-size components.
///
/// Implements a 'Virtual Grid' algorithm to handle span-based items (e.g., large
/// 'Recent Game' cards occupying 3x2 slots) and standard 1x1 system cards.
class SystemCardGridView extends StatefulWidget {
  const SystemCardGridView({
    super.key,
    required this.crossAxisCount,
    this.childAspectRatio = 1,
    this.aspectRatios,
    this.selectedIndex = 0,
    this.onCardTapped,
    this.onEnterPressed,
    this.onEscapePressed,
    this.systems = const [],
  });

  final int crossAxisCount;
  final double childAspectRatio;

  /// Optional per-card aspect ratios. When supplied, each card is laid out with
  /// its own height (width / aspectRatio). This is used to render systems with
  /// hidden logos as perfect 1:1 squares while keeping the logo footer space
  /// for the rest.
  final List<double>? aspectRatios;

  final int selectedIndex;
  final Function(int index)? onCardTapped;
  final VoidCallback? onEnterPressed;
  final VoidCallback? onEscapePressed;
  final List<dynamic> systems;

  @override
  State<SystemCardGridView> createState() => _SystemCardGridViewState();
}

class _SystemCardGridViewState extends State<SystemCardGridView> {
  final ScrollController _scrollController = ScrollController();

  /// Orchestrator for hardware input.
  late GamepadNavigation _gamepadNav;

  /// Effective column count — synced from widget on parent rebuild,
  /// updated immediately on pinch for real-time responsiveness.
  late int _cols;

  /// Throttling mechanism for pointer-based navigation events.
  DateTime? _lastNavigationTime;

  /// Local state to optimize animation curves during high-speed navigation.
  bool _isNavigatingFast = false;

  /// Internal flag tracking the origin of navigation events.
  final bool _gamepadNavigationActive = false;

  /// Pinch gesture tracking for touch-based density changes (raw pointer events).
  final Map<int, Offset> _activePointers = {};
  double? _lastPinchDistance;
  DateTime? _lastPinchTime;

  /// Pull-to-refresh progress notifier (0.0 to 1.0).
  final ValueNotifier<double> _pullProgress = ValueNotifier(0.0);
  static const double _maxPull = 75.0;
  bool _pullReady = false;

  /// Floating card size label shown briefly after pinch-to-zoom.
  final ValueNotifier<String?> _cardSizeLabel = ValueNotifier(null);
  Timer? _cardSizeLabelTimer;

  SecondaryDisplayState? _secondaryDisplayState;

  final Map<String, String?> _themeBackgrounds = {};
  String _lastThemeFolder = '';

  List<List<int>>? _cachedVirtualGrid;
  int? _cachedGridCols;
  int? _cachedGridSystemCount;

  /// Cached conversion of widget.systems to SystemInfo list, rebuilt only on systems change.
  late List<SystemInfo> _systemCards;

  /// Cached ThemeData with scrollbar overrides — rebuilt only in didChangeDependencies.
  ThemeData? _cachedThemeData;
  ScrollBehavior? _cachedScrollBehavior;

  List<SystemInfo> _toSystemCards(List<dynamic> systems) => systems.map((s) {
    if (s is SystemInfo) return s;
    return SystemInfo.fromSystemMetadata(s);
  }).toList();

  /// Bridge so extension parts can request a rebuild
  /// (`State.setState` is `@protected`).
  void rebuild(VoidCallback fn) => setState(fn);

  @override
  void initState() {
    super.initState();
    _systemCards = _toSystemCards(widget.systems);
    _cols = widget.crossAxisCount;
    _initializeGamepad();

    if (Platform.isAndroid) {
      _secondaryDisplayState = SecondaryDisplayState.instance;
      _secondaryDisplayState!.addListener(_onSecondaryStateChanged);
    }

    // Ensure focus and visibility are synchronized after the first layout pass.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _ensureSelectedItemVisibleUniversal();
      }
      _loadThemeAssetsForSystems();
      _onSecondaryStateChanged();
      _updateSecondaryScreenName();
      _precacheSystemBackgrounds();
    });
  }

  bool _prevIsSecondaryActive = false;
  // Tracks the scan-active state across builds so we can re-push the settled
  // selection to the secondary display exactly when the initial scan finishes.
  bool _wasScanning = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final theme = Theme.of(context);
    _cachedThemeData = theme.copyWith(
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStateProperty.all(
          theme.colorScheme.onSurface.withValues(alpha: 0.1),
        ),
        trackColor: WidgetStateProperty.all(
          theme.colorScheme.onSurface.withValues(alpha: 0.05),
        ),
        thickness: WidgetStateProperty.all(6),
        radius: Radius.circular(3.r),
      ),
    );
    _cachedScrollBehavior = ScrollConfiguration.of(
      context,
    ).copyWith(scrollbars: false);
  }

  @override
  void didUpdateWidget(SystemCardGridView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _cols = widget.crossAxisCount;
    if (oldWidget.systems != widget.systems ||
        oldWidget.crossAxisCount != widget.crossAxisCount) {
      _cachedVirtualGrid = null;
      _systemCards = _toSystemCards(widget.systems);
    }
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      if (mounted && _scrollController.hasClients) {
        _ensureSelectedItemVisibleUniversal();
      }
      _updateSecondaryScreenName();
    }
  }

  @override
  void dispose() {
    _cardSizeLabelTimer?.cancel();
    _cardSizeLabel.dispose();
    // Shared singleton — detach our listener, never dispose the instance.
    _secondaryDisplayState?.removeListener(_onSecondaryStateChanged);
    _cleanupGamepad();
    _scrollController.dispose();
    super.dispose();
  }

  /// Generates a logical 2D representation of the grid to resolve complex
  /// directional navigation across items with varying spans.
  ///
  /// Returns a matrix where each cell [row][col] points to the item index.
  /// Memoized wrapper around the pure [buildVirtualGrid]: caches the last
  /// packed grid so repeated navigation/scroll passes over an unchanged card
  /// set skip the recompute.
  List<List<int>> _buildVirtualGrid(List<SystemInfo> cards, int cols) {
    if (_cachedVirtualGrid != null &&
        _cachedGridCols == cols &&
        _cachedGridSystemCount == cards.length) {
      return _cachedVirtualGrid!;
    }

    final grid = buildVirtualGrid(cards, cols);

    _cachedVirtualGrid = grid;
    _cachedGridCols = cols;
    _cachedGridSystemCount = cards.length;
    return grid;
  }

  /// Resolves the live viewport width (net of the outer inset) and delegates to
  /// the pure [calculateGridDimensions]. [customWidth], when supplied (e.g. from
  /// a `LayoutBuilder`'s constraints), is used as-is without the inset.
  Map<String, double> _calculateGridDimensions([double? customWidth]) {
    final screenWidth =
        customWidth ?? (MediaQuery.of(context).size.width - 12.0.r);
    return calculateGridDimensions(
      screenWidth: screenWidth,
      cols: _cols,
      childAspectRatio: widget.childAspectRatio,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: MySystems.gridLaunchNotifier,
      builder: (context, isLaunching, child) {
        if (isLaunching) return const SizedBox.shrink();

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
            // the user navigates and triggers a push.
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

        Widget grid = Theme(
          data: _cachedThemeData ?? Theme.of(context),
          child: ScrollConfiguration(
            behavior:
                _cachedScrollBehavior ??
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: _buildWideCardGrid(context, _systemCards),
          ),
        );

        if (Platform.isAndroid) {
          grid = NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollUpdateNotification) {
                final pixels = notification.metrics.pixels;
                if (pixels < 0) {
                  _pullProgress.value = (-pixels / _maxPull).clamp(0.0, 1.0);
                  if (_pullProgress.value >= 1.0) {
                    _pullReady = true;
                  }
                } else if (_pullProgress.value > 0 && !_pullReady) {
                  _pullProgress.value = 0.0;
                }
              } else if (notification is ScrollEndNotification) {
                _pullReady = false;
                _pullProgress.value = 0.0;
              }
              return false;
            },
            child: grid,
          );

          grid = Listener(
            onPointerDown: _handlePointerDown,
            onPointerMove: _handlePointerMove,
            onPointerUp: _handlePointerUp,
            onPointerCancel: _handlePointerCancel,
            behavior: HitTestBehavior.translucent,
            child: grid,
          );
        }

        return Stack(
          children: [
            grid,
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
            ValueListenableBuilder<String?>(
              valueListenable: _cardSizeLabel,
              builder: (context, label, child) {
                return AnimatedOpacity(
                  opacity: label != null ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: IgnorePointer(
                    child: Center(
                      child: label != null
                          ? Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 20.r,
                                vertical: 10.r,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(24.r),
                              ),
                              child: Text(
                                label,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  fontSize: 18.r,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 2.r,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  /// Renders a non-linear grid by manually positioning components according to their spans.
  ///
  /// System cards can now have per-card aspect ratios (e.g. 1:1 when the system
  /// logo is hidden). Each row's height is derived from the tallest card in that
  /// row, eliminating empty footer space inside the card itself.
  Widget _buildWideCardGrid(
    BuildContext context,
    List<SystemInfo> systemCards,
  ) {
    final cols = _cols;
    final grid = _buildVirtualGrid(systemCards, cols);

    return LayoutBuilder(
      builder: (context, constraints) {
        final dims = _calculateGridDimensions(constraints.maxWidth);
        final colWidth = dims['itemWidth']!;
        final spX = dims['crossAxisSpacing']!;
        final spY = dims['mainAxisSpacing']!;

        /// Resolves the aspect ratio for a card, falling back to the widget default.
        double cardAspectRatio(int index) {
          final ratios = widget.aspectRatios;
          if (ratios != null && index >= 0 && index < ratios.length) {
            return ratios[index];
          }
          return widget.childAspectRatio;
        }

        /// Computes the item height for each row based on the tallest occupant.
        final rowItemHeights = List<double>.filled(grid.length, 0);
        final rowHeights = List<double>.filled(grid.length, 0);
        for (int r = 0; r < grid.length; r++) {
          final seen = <int>{};
          double maxHeight = 0;
          for (int c = 0; c < grid[r].length; c++) {
            final cardIdx = grid[r][c];
            if (cardIdx == -1 || seen.contains(cardIdx)) continue;
            seen.add(cardIdx);
            final height = colWidth / cardAspectRatio(cardIdx);
            if (height > maxHeight) maxHeight = height;
          }
          rowItemHeights[r] = maxHeight;
          rowHeights[r] = maxHeight + spY;
        }

        /// Accumulated top offset for a given row.
        double rowTop(int row) {
          double top = 0;
          for (int i = 0; i < row; i++) {
            top += rowHeights[i];
          }
          return top;
        }

        /// Total scrollable height (last row doesn't add trailing spacing).
        final totalHeight = rowHeights.isEmpty
            ? 0.0
            : rowHeights.reduce((a, b) => a + b) - spY;

        final List<Widget> cardWidgets = [];
        final Set<int> placedIndices = {};

        double? selLeft, selTop, selWidth, selHeight;

        for (int r = 0; r < grid.length; r++) {
          for (int c = 0; c < grid[r].length; c++) {
            final cardIdx = grid[r][c];
            if (cardIdx == -1 || placedIndices.contains(cardIdx)) continue;

            final card = systemCards[cardIdx];
            // The oversized 3x2 "hero" treatment for recent-game cards was
            // designed for wide TV/desktop layouts. On iOS's phone-sized
            // screens it dwarfs every other card, so keep it at the same
            // 1x1 size as everything else there.
            final spanW = (card.isGame && cols >= 3 && !Platform.isIOS)
                ? 3
                : 1;
            final spanH = (card.isGame && cols >= 3 && !Platform.isIOS)
                ? 2
                : 1;

            final left = c * (colWidth + spX);
            final width = spanW * colWidth + (spanW - 1) * spX;

            double cardHeight;
            double top;
            if (card.isGame) {
              cardHeight = 0;
              for (int i = 0; i < spanH && r + i < rowItemHeights.length; i++) {
                cardHeight += rowItemHeights[r + i];
              }
              cardHeight += (spanH - 1) * spY;
              top = rowTop(r);
            } else {
              cardHeight = colWidth / cardAspectRatio(cardIdx);
              // Center the card vertically inside the row band.
              final rowItemHeight = rowItemHeights[r];
              top = rowTop(r) + (rowItemHeight - cardHeight) / 2;
            }

            if (cardIdx == widget.selectedIndex) {
              selLeft = left;
              selTop = top;
              selWidth = width;
              selHeight = cardHeight;
            }

            cardWidgets.add(
              Positioned(
                left: left,
                top: top,
                width: width,
                height: cardHeight,
                child: RepaintBoundary(
                  child: SystemCard(
                    key: ValueKey('system_card_${card.title}_$cardIdx'),
                    info: card,
                    isSelected: cardIdx == widget.selectedIndex,
                    onTap: () {
                      // Touch users have no A button: tapping the card that is
                      // already selected enters it, so reaching for the footer
                      // is only ever optional. (SystemCard plays the sound.)
                      if (cardIdx == widget.selectedIndex) {
                        widget.onEnterPressed?.call();
                        return;
                      }

                      if (_gamepadNavigationActive) {
                        return;
                      }
                      final now = DateTime.now();
                      if (_lastNavigationTime != null &&
                          now.difference(_lastNavigationTime!).inMilliseconds <
                              60) {
                        return;
                      }

                      _lastNavigationTime = now;
                      widget.onCardTapped?.call(cardIdx);
                    },
                  ),
                ),
              ),
            );

            placedIndices.add(cardIdx);
          }
        }

        final focusIndicator =
            (selLeft != null &&
                selTop != null &&
                selWidth != null &&
                selHeight != null)
            ? AnimatedPositioned(
                key: const ValueKey('focus_indicator'),
                duration: const Duration(milliseconds: 256),
                curve: Curves.fastOutSlowIn,
                left: selLeft + 1.r,
                top: selTop + 1.r,
                width: selWidth - 2.r,
                height: selHeight - 2.r,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius:
                          Theme.of(
                            context,
                          ).extension<CornerRadii>()?.radiusExternal ??
                          BorderRadius.circular(14.r),
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.28),
                          Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.08),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.35, 1.0],
                      ),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.55),
                        width: 2.r,
                      ),
                    ),
                  ),
                ),
              )
            : const SizedBox.shrink();

        return SingleChildScrollView(
          controller: _scrollController,
          clipBehavior: Clip.none,
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          child: SizedBox(
            height: totalHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [...cardWidgets, focusIndicator],
            ),
          ),
        );
      },
    );
  }
}
