import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import 'dart:async';
import '../../../models/system_model.dart';
import '../../../models/game_model.dart';
import '../../../providers/file_provider.dart';
import '../../../providers/retro_achievements_provider.dart';
import '../../../sync/i_sync_provider.dart';
import '../../../models/retro_achievements_game_info.dart';
import '../../../repositories/game_repository.dart';
import '../../../services/retro_achievements_helper.dart';
import '../../../utils/artwork_cache.dart';
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
import 'widgets/scraping_progress_panel.dart';
import 'tabs/game_details_general_tab.dart';
import 'tabs/game_details_box2d_tab.dart';
import 'tabs/game_details_screenshot_video_tab.dart';
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

  /// Bumped by the games list whenever this game's artwork files change on
  /// disk — a scrape, or a media file replaced from the settings dialog. The
  /// card folds it into its own version so the artwork tabs reload; without it
  /// they keep the decode they already resolved until another game is selected.
  final int artworkVersion;

  /// True when an external (list-level) scrape is running for this game, e.g.
  /// triggered by the Select button. Drives the scrape button spinner so the
  /// feedback matches a scrape started from the button itself.
  final bool isExternallyScraping;

  /// Progress and step of that external scrape, so the card's progress panel
  /// reports it exactly as it reports a scrape the card started itself.
  final double? externalScrapeProgress;
  final String? externalScrapeStatus;

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
    this.artworkVersion = 0,
    this.isExternallyScraping = false,
    this.externalScrapeProgress,
    this.externalScrapeStatus,
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
  DetailTab _currentTab = DetailTab.wheel;
  final ScrollController _achievementsScrollController = ScrollController();
  int _imageVersion =
      0; // Cache-busting version for images after metadata refreshes.

  /// Cache-busting version for the artwork tabs, covering both the card's own
  /// scrape and artwork the games list saw change underneath it.
  int get _artworkImageVersion => _imageVersion + widget.artworkVersion;

  Future<Uint8List?>? _androidAppIconFuture;
  SecondaryDisplayState? _secondaryState;
  int _lastScrapeTrigger = 0;

  final GlobalKey<GameDetailsAchievementsTabState> _achievementsTabKey =
      GlobalKey<GameDetailsAchievementsTabState>();

  /// Determines if the screenshot/video tab should be suppressed when secondary display is active.
  bool get _isGameInfoHidden {
    if (!widget.isSecondaryScreenActive) return false;
    final config = context.read<SqliteConfigProvider>().config;
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

    _currentTab = DetailTab.wheel;

    // Restore the last tab the user picked with L1/R1. Deferred to the first
    // frame so _setTab can run its side effects (game info overlay, video
    // delay) exactly as it would for a live tab change.
    final restoredTab = _persistedTab();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (restoredTab == DetailTab.wheel) {
        // Reset primary UI 'Game Info' overlay to ensure clean state transitions.
        context.read<SqliteConfigProvider>().updateShowGameInfo(false);
      } else {
        _setTab(restoredTab, persist: false);
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
            ? DetailTab.wheel
            : DetailTab.achievements,
      );
    });

    widget.onRegisterRefreshAchievements?.call(refreshAchievements);

    widget.onToggleVideoMute?.call(_toggleVideoMute);

    widget.onToggleInfo?.call(() {
      if (_currentTab == DetailTab.screenshotVideo &&
          _isScrapingGame == false) {
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
          _currentTab == DetailTab.screenshotVideo
              ? DetailTab.wheel
              : DetailTab.screenshotVideo,
        );
      }
    });

    widget.onRegisterOverlayState?.call(
      () => _currentTab != DetailTab.wheel,
      () => _currentTab == DetailTab.achievements,
    );
    widget.onRegisterCloseOverlays?.call(_closeAllOverlays);
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

    if ((_isGameInfoHidden && _currentTab == DetailTab.screenshotVideo) ||
        (!_hasRetroAchievements && _currentTab == DetailTab.achievements)) {
      _currentTab = DetailTab.wheel;
    }

    widget.onToggleInfo?.call(() {
      _setTab(
        _currentTab == DetailTab.screenshotVideo
            ? DetailTab.wheel
            : DetailTab.screenshotVideo,
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
              isScreenshotVideoHidden: _isGameInfoHidden,
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

          if (_currentTab == DetailTab.wheel)
            GameDetailsGeneralTab(
              system: _effectiveSystem,
              game: _game,
              fileProvider: widget.fileProvider,
              imageVersion: _artworkImageVersion,
              androidAppIconFuture: _androidAppIconFuture,
            ),
          if (_currentTab == DetailTab.box2d)
            GameDetailsBox2dTab(
              system: _effectiveSystem,
              game: _game,
              fileProvider: widget.fileProvider,
              imageVersion: _artworkImageVersion,
            ),
          Visibility(
            visible: _currentTab == DetailTab.screenshotVideo,
            maintainState: true,
            maintainSize: true,
            maintainAnimation: true,
            maintainInteractivity: true,
            child: GameDetailsScreenshotVideoTab(
              screenshotPath: screenshotPath,
              isVideoDelayActive: _isVideoDelayActive,
              videoController: widget.videoController,
              imageVersion: _artworkImageVersion,
              onToggleVideoMute: _toggleVideoMute,
            ),
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
              isScrapingGame: _isScrapingGame || widget.isExternallyScraping,
              onScrapeGame: _onScrapeGameCompact,
            ),
          if (_currentTab == DetailTab.achievements)
            GameDetailsAchievementsTab(
              key: _achievementsTabKey,
              gameInfo: _currentGameInfo,
              isLoading: _isLoadingAchievements,
              onRefresh: refreshAchievements,
            ),

          // Scrape feedback for every tab. A scrape can start from any of them
          // (the Scrape button, Select + A, or the games list), so it is drawn
          // over the tab panels rather than inside one of them.
          if (_isScrapingGame || widget.isExternallyScraping)
            ScrapingProgressPanel(
              progress: _isScrapingGame
                  ? _scrapeProgress
                  : (widget.externalScrapeProgress ?? 0.0),
              status: _isScrapingGame
                  ? _scrapeStatus
                  : (widget.externalScrapeStatus ?? ''),
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

    // No tab switch at all: the progress panel overlays whichever tab is open,
    // so the user stays where they were — and the tab they chose stays the
    // remembered one (#284).
    _startSingleGameScrape(forceOverwrite: !isDescriptionMissing);
  }

  /// Renders the background fanart with smooth cross-fades and scale animations.

  void _handleTriggerAction() {
    if (_currentTab == DetailTab.achievements) {
      if (_scrapeButtonFocusNode.hasFocus) {
        refreshAchievements();
      }
      return;
    }

    if (_currentTab == DetailTab.gameInfo ||
        _currentTab == DetailTab.screenshotVideo) {
      if (_scrapeButtonFocusNode.hasFocus) {
        _startSingleGameScrape();
      }
    }
  }

  /// Handles secondary hardware actions (typically mapped to X or RB).
  void _handleSecondaryAction() {
    // Unchanged condition — the action stays tied to the screenshot tab being
    // available — but it no longer switches to that tab: the progress panel
    // overlays whichever tab the user is on.
    if (_isGameInfoHidden) return;

    if (_isScrapingGame) return;

    _startSingleGameScrape();
  }

  /// Whether [tab] can be shown for the current game and display setup.
  bool _isTabAvailable(DetailTab tab) {
    if (tab == DetailTab.screenshotVideo && _isGameInfoHidden) return false;
    if (tab == DetailTab.achievements && !_hasRetroAchievements) return false;
    return true;
  }

  /// Resolves the persisted tab preference into a tab usable right now.
  ///
  /// An unknown name (config written by another build) or a tab this game
  /// can't show falls back to the wheel, leaving the stored preference intact
  /// so it returns on a game that supports it.
  DetailTab _persistedTab() {
    final storedName = context
        .read<SqliteConfigProvider>()
        .config
        .gameDetailsTab;
    final tab = DetailTab.values.firstWhere(
      (t) => t.name == storedName,
      orElse: () => DetailTab.wheel,
    );
    return _isTabAvailable(tab) ? tab : DetailTab.wheel;
  }

  /// Processes tab navigation via hardware bumpers (LB/RB).
  bool _handleTabNavigation(bool isRight) {
    if (!mounted) return false;

    final availableTabs = DetailTab.values.where(_isTabAvailable).toList();

    int currentIndexInAvailable = availableTabs.indexOf(_currentTab);
    if (currentIndexInAvailable == -1) currentIndexInAvailable = 0;

    int nextIndex =
        (currentIndexInAvailable + (isRight ? 1 : -1)) % availableTabs.length;
    if (nextIndex < 0) nextIndex = availableTabs.length - 1;

    _setTab(availableTabs[nextIndex]);
    return true; // Input consumed.
  }

  /// Switches to [tab].
  ///
  /// [persist] records the tab as the user's preference so it carries across
  /// games, systems and restarts; it is disabled for tabs the app forces on the
  /// user (a scrape jumping to the media tab, or restoring the stored tab).
  void _setTab(DetailTab tab, {bool persist = true}) {
    if (_currentTab == tab) return;

    final wasScreenshotVideo = _currentTab == DetailTab.screenshotVideo;

    setState(() {
      _currentTab = tab;

      final config = context.read<SqliteConfigProvider>();
      if (persist) {
        config.updateGameDetailsTab(tab.name);
      }
      if (tab == DetailTab.screenshotVideo) {
        config.updateShowGameInfo(true);
        widget.videoController?.setVolume(0);
        _startVideoDelay();
      } else {
        if (config.config.showGameInfo) {
          config.updateShowGameInfo(false);
        }
        if (wasScreenshotVideo) {
          _cancelVideoDelay();
        }
        if (tab == DetailTab.wheel &&
            widget.videoController != null &&
            widget.showVideo) {
          _applyVideoMuteState();
        }
      }
    });
  }

  void _closeAllOverlays() {
    // Dismissing an overlay isn't a tab choice, so it leaves the preference be.
    _setTab(DetailTab.wheel, persist: false);
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

    // No "scraping…" toast: the progress panel above says the same thing for
    // the whole run, wherever the scrape was started from.
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
          // Evict every artwork file the scrape may have rewritten — box art
          // included — so the tabs below reload them instead of redrawing the
          // decoded copies they were already showing.
          await evictScrapedArtwork(
            scrapedArtworkPaths(_game, targetSystemFolder, widget.fileProvider),
          );

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
