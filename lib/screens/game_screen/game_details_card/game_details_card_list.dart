import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import 'dart:io';
import 'dart:async';
import '../../../models/system_model.dart';
import '../../../models/game_model.dart';
import '../../../providers/file_provider.dart';
import '../../../providers/retro_achievements_provider.dart';
import '../../../sync/i_sync_provider.dart';
import '../../../models/retro_achievements_game_info.dart';
import '../../../repositories/game_repository.dart';
import '../../../services/retro_achievements_helper.dart';
import '../../../utils/gamepad_nav.dart';
import 'package:flutter/foundation.dart';

import 'package:provider/provider.dart';
import '../../../providers/sqlite_config_provider.dart';
import '../../../services/screenscraper_service.dart';
import '../../../services/game_service.dart';
import '../../../services/android_service.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/widgets/custom_notification.dart';
import '../../../models/secondary_display_state.dart';
import 'widgets/game_details_footer.dart';
import 'widgets/game_details_tabs_header.dart';
import 'tabs/game_details_general_tab.dart';
import 'tabs/game_details_game_info_tab.dart';
import 'tabs/game_details_achievements_tab.dart';

/// A comprehensive details view for a selected game, providing access to metadata,
/// achievements, system settings, and cloud synchronization status.
///
/// This component orchestrates complex interactions between RetroAchievements APIs,
/// ScreenScraper metadata resolution, and local SQLite persistence.
class GameDetailsCardList extends StatefulWidget {
  final GameModel game;
  final SystemModel system;
  final FileProvider fileProvider;
  final bool showVideo;
  final VideoPlayerController? videoController;
  final bool isVideoLoading;
  final bool isAllMode;
  final RetroAchievementsProvider retroAchievementsProvider;
  final ISyncProvider syncProvider;
  final String? localizedDescription;

  /// True when an external (list-level) scrape is running for this game, e.g.
  /// triggered by the Select button. Drives the scrape button spinner so the
  /// feedback matches a scrape started from the button itself.
  final bool isExternallyScraping;

  final VoidCallback? onDeactivateNavigation;
  final VoidCallback? onReactivateNavigation;
  final void Function(VoidCallback)? onShowAchievements;
  final void Function(VoidCallback)? onRegisterRefreshAchievements;
  final Function(Function())? onToggleVideoMute;
  final Function(Function())? onToggleInfo;

  /// Callback to register overlay state getters for external navigation management.
  final Function(
    bool Function() isOverlayOpen,
    bool Function() isAchievementsOpen,
  )?
  onRegisterOverlayState;

  /// Callback to register navigation methods for high-level input redirection.
  final Function({
    required VoidCallback moveUp,
    required VoidCallback moveDown,
    required VoidCallback moveLeft,
    required VoidCallback moveRight,
  })?
  onRegisterNavigation;

  /// Callback to register the close overlays method.
  final Function(VoidCallback)? onRegisterCloseOverlays;

  final VoidCallback? onPlayGame;
  final VoidCallback? onShowRandomGame;
  final VoidCallback? onGameUpdated;
  final VoidCallback? onFavoriteToggled;
  final void Function(String romname)? onGameDeleted;

  /// Callback to register the primary trigger action (standard Gamepad A).
  final Function(VoidCallback)? onRegisterTriggerAction;

  /// Callback to register the secondary action (standard Gamepad RB).
  final Function(VoidCallback)? onRegisterSecondaryAction;

  /// Callback to register a predicate that blocks game launching (e.g., during settings).
  final Function(bool Function())? onRegisterIsPlayingGameBlocked;

  /// Callback to register tab-based navigation handling (Gamepad L/R bumpers).
  final Function(bool Function(bool))? onRegisterTabNavigation;

  /// Callback to register the Select button action.
  final Function(VoidCallback)? onRegisterSelectButton;

  /// Callback to register the scrape action (Select + A combo).
  final Function(VoidCallback)? onRegisterScrapeAction;

  final bool isSecondaryScreenActive;
  final bool isNavigatingFast;
  final VoidCallback? onBack;

  const GameDetailsCardList({
    super.key,
    required this.game,
    required this.system,
    required this.fileProvider,
    this.showVideo = false,
    this.videoController,
    this.isVideoLoading = false,
    this.isAllMode = false,
    required this.retroAchievementsProvider,
    required this.syncProvider,
    this.localizedDescription,
    this.isExternallyScraping = false,
    this.onDeactivateNavigation,
    this.onReactivateNavigation,
    this.onShowAchievements,
    this.onRegisterRefreshAchievements,
    this.onToggleVideoMute,
    this.onToggleInfo,
    this.onRegisterOverlayState,
    this.onRegisterNavigation,
    this.onRegisterCloseOverlays,
    this.onPlayGame,
    this.onShowRandomGame,
    this.onGameUpdated,
    this.onFavoriteToggled,
    this.onGameDeleted,
    this.onRegisterTriggerAction,
    this.onRegisterSecondaryAction,
    this.onRegisterIsPlayingGameBlocked,
    this.onRegisterTabNavigation,
    this.onRegisterSelectButton,
    this.onRegisterScrapeAction,
    this.isSecondaryScreenActive = false,
    this.isNavigatingFast = false,
    this.onBack,
  });

  @override
  State<GameDetailsCardList> createState() => _GameDetailsCardListState();
}

class _GameDetailsCardListState extends State<GameDetailsCardList>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late AnimationController _syncIconController;

  static final _log = LoggerService.instance;

  // Local state for the game model to reflect dynamic updates (e.g., scraping).
  late GameModel _game;

  // RetroAchievements Integration state.
  GameInfoAndUserProgress? _currentGameInfo;
  bool _isLoadingAchievements = false;

  // Media playback configuration state.
  bool _isLoadingVideoConfig = true;

  // Cloud Synchronization state.
  late bool _cloudSyncEnabled;

  // ScreenScraper / Metadata acquisition state.
  bool _isScrapingGame = false;
  late final FocusNode _scrapeButtonFocusNode;

  // Navigation management: Explicit focus nodes for UI control points.
  late final FocusNode _muteButtonFocusNode;
  late final FocusNode _achievementsButtonFocusNode;
  late final FocusNode _favoriteButtonFocusNode;

  // Resource lifecycle and deferred timers.
  bool _isVideoDelayActive = false;
  Timer? _videoDelayTimer;
  double _scrapeProgress = 0.0;
  String _scrapeStatus = '';

  // View state: Current active tab and scrolling context.
  DetailTab _currentTab = DetailTab.general;
  final ScrollController _achievementsScrollController = ScrollController();
  int _imageVersion =
      0; // Cache-busting version for images after metadata refreshes.

  Future<Uint8List?>? _androidAppIconFuture;
  SecondaryDisplayState? _secondaryState;
  int _lastScrapeTrigger = 0;

  final GlobalKey<GameDetailsAchievementsTabState> _achievementsTabKey =
      GlobalKey<GameDetailsAchievementsTabState>();

  /// Determines if the detailed game info tab should be suppressed in favor of secondary display output.
  bool get _isGameInfoHidden {
    if (!widget.isSecondaryScreenActive) return false;
    final config = context.read<SqliteConfigProvider>().config;
    // If secondary display is active and not explicitly hidden in config, suppress primary UI info.
    return !config.hideBottomScreen;
  }

  /// Resolves the actual hardware system for the game.
  /// Handles 'Global Library' (isAllMode) resolution from detected systems.
  SystemModel get _effectiveSystem {
    if (!widget.isAllMode) return widget.system;

    final systemFolderName = _game.systemFolderName;
    if (systemFolderName == null) return widget.system;

    try {
      final detectedSystems = context
          .read<SqliteConfigProvider>()
          .detectedSystems;
      return detectedSystems.firstWhere(
        (s) => s.folderName == systemFolderName,
        orElse: () => widget.system,
      );
    } catch (e) {
      return widget.system;
    }
  }

  /// Predicate indicating if RetroAchievements integration is technically feasible for this hardware.
  bool get _hasRetroAchievements =>
      _effectiveSystem.raId != null &&
      _effectiveSystem.raId != '0' &&
      _effectiveSystem.raId!.isNotEmpty;

  /// Predicate indicating if ScreenScraper support is configured for this system.
  bool get _hasScreenScraper =>
      _effectiveSystem.screenscraperId != null &&
      _effectiveSystem.screenscraperId != 0;

  @override
  void initState() {
    super.initState();
    _game = widget.game;
    _cloudSyncEnabled = widget.game.cloudSyncEnabled ?? true;

    _muteButtonFocusNode = FocusNode();
    _achievementsButtonFocusNode = FocusNode();
    _favoriteButtonFocusNode = FocusNode();
    _scrapeButtonFocusNode = FocusNode();

    _currentTab = DetailTab.general;

    // Reset primary UI 'Game Info' overlay to ensure clean state transitions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<SqliteConfigProvider>().updateShowGameInfo(false);
      }
    });

    if (_effectiveSystem.folderName == 'android') {
      _androidAppIconFuture = AndroidService.getAppIcon(
        widget.game.romPath ?? '',
      );
    }

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _syncIconController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _verifyCloudSyncStatus();

    // Trigger achievement hydration unless the user is rapidly scrolling through the library.
    if (!widget.isNavigatingFast) {
      _loadAchievementsForGame();
    }

    widget.retroAchievementsProvider.addListener(_onRAProviderChanged);

    // Register delegates for external UI coordination.
    widget.onShowAchievements?.call(() {
      _setTab(
        _currentTab == DetailTab.achievements
            ? DetailTab.general
            : DetailTab.achievements,
      );
    });

    widget.onRegisterRefreshAchievements?.call(refreshAchievements);

    widget.onToggleVideoMute?.call(_toggleVideoMute);

    // Info toggle: Triggers metadata scraping if information is missing.
    widget.onToggleInfo?.call(() {
      if (_currentTab == DetailTab.gameInfo && _isScrapingGame == false) {
        if (_game.getDescriptionForLanguage('en').isEmpty ||
            _game.getDescriptionForLanguage('en') ==
                'No description available.') {
          _startSingleGameScrape();
        } else {
          _startSingleGameScrape(forceOverwrite: true);
        }
      } else if (_currentTab == DetailTab.achievements) {
        refreshAchievements();
      } else {
        _setTab(
          _currentTab == DetailTab.gameInfo
              ? DetailTab.general
              : DetailTab.gameInfo,
        );
      }
    });

    widget.onRegisterOverlayState?.call(
      () => _currentTab != DetailTab.general,
      () => _currentTab == DetailTab.achievements,
    );
    widget.onRegisterCloseOverlays?.call(() {
      _setTab(DetailTab.general);
    });
    widget.onRegisterTabNavigation?.call(_handleTabNavigation);
    widget.onRegisterSelectButton?.call(_handleSelectAction);
    widget.onRegisterScrapeAction?.call(_onScrapeGameCompact);
    widget.onRegisterNavigation?.call(
      moveUp: () {
        if (_currentTab == DetailTab.achievements) {
          _achievementsTabKey.currentState?.moveUp();
        }
      },
      moveDown: () {
        if (_currentTab == DetailTab.achievements) {
          _achievementsTabKey.currentState?.moveDown();
        }
      },
      moveLeft: () {
        if (_currentTab == DetailTab.achievements) {
          _achievementsTabKey.currentState?.moveLeft();
        }
      },
      moveRight: () {
        if (_currentTab == DetailTab.achievements) {
          _achievementsTabKey.currentState?.moveRight();
        }
      },
    );
    widget.onRegisterTriggerAction?.call(_handleTriggerAction);
    widget.onRegisterSecondaryAction?.call(_handleSecondaryAction);
    widget.onRegisterCloseOverlays?.call(_closeAllOverlays);

    _loadVideoConfig();

    _secondaryState = context.read<SecondaryDisplayState?>();
    _lastScrapeTrigger = _secondaryState?.value?.scrapeTrigger ?? 0;
    _secondaryState?.addListener(_onSecondaryStateChanged);
  }

  /// Retries achievement loading when the provider re-establishes connectivity or session data.
  void _onRAProviderChanged() {
    if (!mounted || _isLoadingAchievements || _currentGameInfo != null) return;
    if (!_hasRetroAchievements) return;
    if (widget.retroAchievementsProvider.isConnected) {
      _loadAchievementsForGame();
    }
  }

  /// Orchestrates background metadata updates triggered by secondary display interactions.
  void _onSecondaryStateChanged() {
    final state = _secondaryState?.value;
    if (state == null) return;

    if (state.scrapeTrigger > _lastScrapeTrigger) {
      _lastScrapeTrigger = state.scrapeTrigger;
      _startSingleGameScrape();
    }
  }

  @override
  void didUpdateWidget(GameDetailsCardList oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Identity check: If the selected game or its source system changes, reset all local states.
    if (!identical(oldWidget.game, widget.game) ||
        oldWidget.game.romname != widget.game.romname ||
        oldWidget.game.systemFolderName != widget.game.systemFolderName ||
        oldWidget.game.name != widget.game.name ||
        oldWidget.game.showRomFileNameSubtitle !=
            widget.game.showRomFileNameSubtitle) {
      setState(() {
        _game = widget.game;
        _cloudSyncEnabled = _game.cloudSyncEnabled ?? true;
        _currentGameInfo = null;
        _isLoadingAchievements = false;

        if (_effectiveSystem.folderName == 'android') {
          _androidAppIconFuture = AndroidService.getAppIcon(
            widget.game.romPath ?? '',
          );
        }
      });

      if (!widget.isNavigatingFast) {
        _loadAchievementsForGame(forceRefresh: false);
      }
      _verifyCloudSyncStatus();

      if (widget.showVideo) {
        _loadVideoConfig();
      }
    } else if (oldWidget.isNavigatingFast && !widget.isNavigatingFast) {
      // Transition from rapid scroll: resume heavy resource hydration.
      _loadAchievementsForGame(forceRefresh: false);
      _verifyCloudSyncStatus();
    }

    if (oldWidget.retroAchievementsProvider !=
        widget.retroAchievementsProvider) {
      oldWidget.retroAchievementsProvider.removeListener(_onRAProviderChanged);
      widget.retroAchievementsProvider.addListener(_onRAProviderChanged);
    }

    if (oldWidget.videoController != widget.videoController ||
        oldWidget.isSecondaryScreenActive != widget.isSecondaryScreenActive) {
      _applyVideoMuteState();
    }

    // Dynamic UI constraints: exit tabs if their requirements are no longer met.
    if ((_isGameInfoHidden && _currentTab == DetailTab.gameInfo) ||
        (!_hasRetroAchievements && _currentTab == DetailTab.achievements)) {
      _currentTab = DetailTab.general;
    }

    widget.onToggleInfo?.call(() {
      _setTab(
        _currentTab == DetailTab.gameInfo
            ? DetailTab.general
            : DetailTab.gameInfo,
      );
    });
  }

  void _handleSelectAction() {
    // Achievements owns Select for its refresh; everywhere else the preview
    // video is what's playing, so Select mutes it (the general tab included —
    // that's where the video is usually watched).
    if (_currentTab == DetailTab.achievements) {
      refreshAchievements();
    } else {
      _toggleVideoMute();
    }
  }

  @override
  void dispose() {
    widget.retroAchievementsProvider.removeListener(_onRAProviderChanged);
    _secondaryState?.removeListener(_onSecondaryStateChanged);
    _animationController.dispose();
    _syncIconController.dispose();
    _videoDelayTimer?.cancel();
    _muteButtonFocusNode.dispose();
    _achievementsButtonFocusNode.dispose();
    _favoriteButtonFocusNode.dispose();
    _scrapeButtonFocusNode.dispose();
    _achievementsScrollController.dispose();
    super.dispose();
  }

  /// Initiates a 3-second aesthetic delay before transitioning to video playback.
  void _startVideoDelay() {
    _videoDelayTimer?.cancel();

    setState(() {
      _isVideoDelayActive = true;
    });

    _videoDelayTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _isVideoDelayActive = false;
        });

        if (widget.videoController?.value.isInitialized == true) {
          widget.videoController?.play();
        }
      }
    });
  }

  /// Gracefully terminates video preview playback and cancels pending transition timers.
  void _cancelVideoDelay() {
    _videoDelayTimer?.cancel();
    _videoDelayTimer = null;
    setState(() {
      _isVideoDelayActive = false;
    });
    if (widget.videoController?.value.isPlaying == true) {
      widget.videoController?.pause();
    }
  }

  /// Loads RetroAchievements data for the current game, including MD5 hash generation.
  Future<void> _loadAchievementsForGame({bool forceRefresh = false}) async {
    final gameTarget = widget.game;

    if (_isLoadingAchievements) {
      // Concurrent load protection: prevents redundant API calls for the same entity.
    }

    setState(() {
      _isLoadingAchievements = true;
    });

    try {
      final gameInfo = await RetroAchievementsHelper.loadGameInfo(
        game: gameTarget,
        provider: widget.retroAchievementsProvider,
        effectiveSystem: _effectiveSystem,
        isAllMode: widget.isAllMode,
        forceRefresh: forceRefresh,
      );

      if (widget.game.romname != gameTarget.romname) return;

      if (mounted && widget.game.romname == gameTarget.romname) {
        if (forceRefresh) {
          RetroAchievementsHelper.evictBadgeCache(_currentGameInfo);
        }

        setState(() {
          _currentGameInfo = gameInfo;
          _isLoadingAchievements = false;
        });
      }
    } catch (e) {
      _log.e('Error loading achievements for game ${gameTarget.name}: $e');
      if (mounted && widget.game.romname == gameTarget.romname) {
        setState(() {
          _currentGameInfo = null;
          _isLoadingAchievements = false;
        });
      }
    }
  }

  /// Triggers a manual synchronization of RetroAchievements data.
  void refreshAchievements() {
    if (!mounted) {
      return;
    }
    setState(() {
      _currentGameInfo = null;
    });
    _loadAchievementsForGame(forceRefresh: true);
  }

  /// Hydrates initial media configuration.
  Future<void> _loadVideoConfig() async {
    if (mounted) {
      setState(() {
        _isLoadingVideoConfig = false;
      });
    }
    await _applyVideoMuteState();
  }

  /// Synchronizes video player volume with user preferences and system constraints.
  Future<void> _applyVideoMuteState() async {
    final configProvider = Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    );
    final isGlobalMuted = !configProvider.config.videoSound;

    // Audio Arbitration: If a secondary display is active with sound, mute the primary UI
    // to prevent acoustic interference.
    final shouldBeMuted = isGlobalMuted || widget.isSecondaryScreenActive;

    if (widget.videoController != null &&
        widget.videoController!.value.isInitialized &&
        !_isLoadingVideoConfig) {
      await widget.videoController!.setVolume(shouldBeMuted ? 0.0 : 1.0);
    }
  }

  /// Toggles global video sound and synchronizes state with the persistence provider.
  Future<void> _toggleVideoMute() async {
    final configProvider = Provider.of<SqliteConfigProvider>(
      context,
      listen: false,
    );
    await configProvider.toggleVideoSound();
    await _applyVideoMuteState();
  }

  @override
  Widget build(BuildContext context) {
    final imageSystemFolder = _effectiveSystem.primaryFolderName;
    final screenshotPath = _game.getImagePath(
      imageSystemFolder,
      'screenshots',
      widget.fileProvider,
    );
    return Card(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(0.r)),
      shadowColor: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Header Layer: Tab navigation and system status.
          Positioned(
            left: 0.r,
            right: 0.r,
            top: 0.r,
            child: GameDetailsTabsHeader(
              isGameInfoHidden: _isGameInfoHidden,
              hasRetroAchievements: _hasRetroAchievements,
              currentTab: _currentTab,
              onTabChanged: (tab) => _setTab(tab),
            ),
          ),

          // Footer Layer: Action bar and synchronization status.
          GameDetailsFooter(
            system: _effectiveSystem,
            game: _game,
            isMusicSystem: _effectiveSystem.folderName == 'music',
            hasScreenScraper: _hasScreenScraper,
            isSecondaryScreenActive: widget.isSecondaryScreenActive,
            cloudSyncEnabled: _cloudSyncEnabled,
            syncProvider: widget.syncProvider,
            syncIconController: _syncIconController,
            onPlayGame: () => widget.onPlayGame?.call(),
            onShowAchievements: () => _setTab(DetailTab.achievements),
            hasRetroAchievements: _hasRetroAchievements,
            isLoadingAchievements: _isLoadingAchievements,
            currentGameInfo: _currentGameInfo,
          ),

          // Dynamic Content Layer: Selected Tab View.
          if (_currentTab == DetailTab.general)
            GameDetailsGeneralTab(
              system: _effectiveSystem,
              game: _game,
              fileProvider: widget.fileProvider,
              androidAppIconFuture: _androidAppIconFuture,
            ),
          if (_currentTab == DetailTab.gameInfo)
            GameDetailsGameInfoTab(
              system: _effectiveSystem,
              game: _game,
              fileProvider: widget.fileProvider,
              description:
                  widget.localizedDescription ??
                  (_game.getDescriptionForLanguage('en').isEmpty
                      ? AppLocale.noDescription.getString(context)
                      : _game.getDescriptionForLanguage('en')),
              screenshotPath: screenshotPath,
              isScrapingGame: _isScrapingGame || widget.isExternallyScraping,
              scrapeProgress: _scrapeProgress,
              scrapeStatus: _scrapeStatus,
              isSecondaryScreenActive: widget.isSecondaryScreenActive,
              isVideoDelayActive: _isVideoDelayActive,
              videoController: widget.videoController,
              imageVersion: _imageVersion,
              onToggleVideoMute: _toggleVideoMute,
              onScrapeGame: _onScrapeGameCompact,
            ),
          if (_currentTab == DetailTab.achievements)
            GameDetailsAchievementsTab(
              key: _achievementsTabKey,
              gameInfo: _currentGameInfo,
              isLoading: _isLoadingAchievements,
              onRefresh: refreshAchievements,
            ),
        ],
      ),
    );
  }

  /// Orchestrates a quick-access metadata scrape.
  void _onScrapeGameCompact() {
    final description =
        widget.localizedDescription ??
        (_game.getDescriptionForLanguage('en').isEmpty
            ? AppLocale.noDescription.getString(context)
            : _game.getDescriptionForLanguage('en'));

    final bool isDescriptionMissing =
        description.isEmpty ||
        description == AppLocale.noDescription.getString(context) ||
        description.trim().isEmpty;

    if (!widget.isSecondaryScreenActive) {
      _setTab(DetailTab.gameInfo);
    }
    // Force metadata overwrite if a valid description is already present.
    _startSingleGameScrape(forceOverwrite: !isDescriptionMissing);
  }

  /// Renders the background fanart with smooth cross-fades and scale animations.

  /// Directs primary gamepad inputs (A Button) based on the currently active tab.
  void _handleTriggerAction() {
    // Achievements Tab: Triggers a data refresh.
    if (_currentTab == DetailTab.achievements) {
      if (_scrapeButtonFocusNode.hasFocus) {
        refreshAchievements();
      }
      return;
    }

    // Metadata Tab: Initiates scraping if the dedicated button is focused.
    if (_currentTab == DetailTab.gameInfo) {
      if (_scrapeButtonFocusNode.hasFocus) {
        _startSingleGameScrape();
      }
    }
  }

  /// Handles secondary hardware actions (typically mapped to X or RB).
  void _handleSecondaryAction() {
    if (!_isGameInfoHidden) {
      _setTab(DetailTab.gameInfo);
    } else {
      // If primary UI is hidden (OLED secondary screen optimization), skip navigation.
      return;
    }

    if (_isScrapingGame) return;

    _startSingleGameScrape();
  }

  /// Processes tab navigation via hardware bumpers (LB/RB).
  bool _handleTabNavigation(bool isRight) {
    if (!mounted) return false;

    // Resolve which tabs are logically available for the current context.
    final availableTabs = DetailTab.values.where((tab) {
      if (tab == DetailTab.gameInfo && _isGameInfoHidden) return false;
      if (tab == DetailTab.achievements && !_hasRetroAchievements) return false;
      return true;
    }).toList();

    int currentIndexInAvailable = availableTabs.indexOf(_currentTab);
    if (currentIndexInAvailable == -1) currentIndexInAvailable = 0;

    int nextIndex =
        (currentIndexInAvailable + (isRight ? 1 : -1)) % availableTabs.length;
    if (nextIndex < 0) nextIndex = availableTabs.length - 1;

    _setTab(availableTabs[nextIndex]);
    return true; // Input consumed.
  }

  /// Updates the active tab and synchronizes required global state (e.g., video mute during info browsing).
  void _setTab(DetailTab tab) {
    if (_currentTab == tab) return;

    final wasGameInfo = _currentTab == DetailTab.gameInfo;

    setState(() {
      _currentTab = tab;

      final config = context.read<SqliteConfigProvider>();
      if (tab == DetailTab.gameInfo) {
        config.updateShowGameInfo(true);
        widget.videoController?.setVolume(0);
        _startVideoDelay();
      } else {
        if (config.config.showGameInfo) {
          config.updateShowGameInfo(false);
        }
        if (wasGameInfo) {
          _cancelVideoDelay();
        }
        if (tab == DetailTab.general &&
            widget.videoController != null &&
            widget.showVideo) {
          _applyVideoMuteState();
        }
      }
    });
  }

  /// Closes all open metadata/achievement overlays, returning to the general view.
  void _closeAllOverlays() {
    _setTab(DetailTab.general);
  }

  /// Orchestrates a metadata acquisition process via ScreenScraperService.
  Future<void> _startSingleGameScrape({bool forceOverwrite = true}) async {
    if (_isScrapingGame) return;

    // Safety: Pause video previews to avoid resource contention or audio leaks during scraping.
    if (widget.videoController != null) {
      try {
        await widget.videoController!.pause();
      } catch (e) {
        _log.e('Error pausing video preview: $e');
      }
    }

    final scrapeSystemId = _effectiveSystem.id;
    if (scrapeSystemId == null) {
      if (!mounted) return;
      AppNotification.showNotification(
        context,
        'Error: System ID is missing.',
        type: NotificationType.error,
      );
      return;
    }

    if (!context.mounted) return;

    if (!await ScreenScraperService.hasSavedCredentials()) {
      if (!mounted) return;
      AppNotification.showNotification(
        context,
        'Please log in to ScreenScraper in the Scraping tab first.',
        type: NotificationType.info,
      );
      return;
    }

    setState(() {
      _isScrapingGame = true;
    });

    if (!mounted) return;

    // Surface immediate feedback — a scrape takes several seconds and can be
    // triggered "blind" via the Select + A chord from the games list.
    AppNotification.showNotification(
      context,
      AppLocale.scrapingGameData.getString(context),
      type: NotificationType.info,
    );

    final secondaryState = context.read<SecondaryDisplayState?>();
    if (secondaryState != null && widget.isSecondaryScreenActive) {
      secondaryState.updateState(
        isScraping: true,
        scrapeStatus: AppLocale.scrapingGameData.getString(context),
        scrapeProgress: 0.0,
      );
    }

    try {
      final targetSystemFolder =
          widget.isAllMode && _game.systemFolderName != null
          ? _game.systemFolderName!
          : widget.system.primaryFolderName;

      final result = await ScreenScraperService.scrapeSingleGame(
        appSystemId: scrapeSystemId,
        romName: _game.romname,
        systemFolder: targetSystemFolder,
        romPath: _game.romPath ?? '',
        gameName: _game.name,
        forceOverwrite: forceOverwrite,
        onProgress: (statusKey, progress) {
          if (!context.mounted) return;
          final localizedStatus = statusKey.getString(context);
          setState(() {
            _scrapeStatus = localizedStatus;
            _scrapeProgress = progress;
          });
          if (secondaryState != null && widget.isSecondaryScreenActive) {
            secondaryState.updateState(
              scrapeStatus: localizedStatus,
              scrapeProgress: progress,
            );
          }
        },
      );

      if (mounted) {
        if (result['success'] == true) {
          // Protocol: Evict all cached artwork to force immediate UI refresh with new assets.
          try {
            final imagesToEvict = [
              _game.getScreenshotPath(targetSystemFolder),
              _game.getImagePath(
                targetSystemFolder,
                'wheels',
                widget.fileProvider,
              ),
              _game.getImagePath(
                targetSystemFolder,
                'fanarts',
                widget.fileProvider,
              ),
            ];

            for (final imagePath in imagesToEvict) {
              final imageFile = File(imagePath);
              if (await imageFile.exists()) {
                await FileImage(imageFile).evict();
              }
            }
          } catch (e) {
            _log.e('Image cache eviction failed: $e');
          }

          if (!context.mounted) return;

          // Hydrate updated entity from persistence.
          final updatedGame = await GameService.getGameDetails(
            _effectiveSystem,
            _game.romname,
          );

          if (mounted && updatedGame != null) {
            setState(() {
              _game = updatedGame;
              _imageVersion++; // Increment version to bust visual caches.
            });

            _loadAchievementsForGame(forceRefresh: true);

            widget.onGameUpdated?.call();

            AppNotification.showNotification(
              context,
              AppLocale.scrapeSuccessful.getString(context),
              type: NotificationType.success,
            );
          }
        } else {
          AppNotification.showNotification(
            context,
            result['message'].toString().getString(context),
            type: NotificationType.error,
          );
        }
      }
    } catch (e) {
      _log.e('Single game scrape operation failed: $e');
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.scrapeErrorGame.getString(context),
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isScrapingGame = false;
        });
        if (secondaryState != null && widget.isSecondaryScreenActive) {
          // Post-scrape latency buffer to ensure file system descriptors are released.
          await Future.delayed(const Duration(milliseconds: 250));

          secondaryState.updateState(
            isScraping: false,
            clearScrapeProgress: true,
            clearScrapeStatus: true,
          );
        }
      }
    }
  }

  /// Synchronizes the actual cloud sync authorization status from the local database.
  Future<void> _verifyCloudSyncStatus() async {
    try {
      final targetSystemFolder =
          widget.isAllMode && widget.game.systemFolderName != null
          ? widget.game.systemFolderName!
          : widget.system.folderName;

      final isEnabled = await GameRepository.isCloudSyncEnabled(
        targetSystemFolder,
        widget.game.romname,
      );

      if (mounted && _cloudSyncEnabled != isEnabled) {
        setState(() {
          _cloudSyncEnabled = isEnabled;
        });
      }
    } catch (e) {
      _log.e('Cloud sync status verification failed: $e');
    }
  }
}
