import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/sync/sync_manager.dart';
import 'package:neostation/providers/theme_provider.dart';
import 'package:neostation/providers/neo_assets_provider.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'dart:async';
import '../../services/game_service.dart';
import '../../utils/game_launch_utils.dart';
import '../../services/music_player_service.dart';
import '../../repositories/system_repository.dart';
import '../../repositories/game_repository.dart';
import '../../services/screenscraper_service.dart';
import '../../services/secondary_achievements_controller.dart';
import '../../utils/gamepad_nav.dart';
import '../../providers/file_provider.dart';
import '../../providers/sqlite_config_provider.dart';
import '../../providers/sqlite_database_provider.dart';
import '../../models/system_model.dart';
import '../../models/game_model.dart';
import 'game_details_card/game_details_card_list.dart';
import 'game_details_card/random_game_dialog.dart';
import 'my_games_grid.dart';
import 'my_games_carousel.dart';
import 'game_list_view.dart';
import 'music/music_list.dart';
import 'music/music_player.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../providers/system_background_provider.dart';
import '../../models/secondary_display_state.dart';
import '../../widgets/game_view_mode_dropdown.dart';
import '../../constants/system_folder_names.dart';
import '../../themes/corner_radii.dart';

part 'my_games_list/gamepad_nav.dart';

/// A high-fidelity list component for browsing games within a specific system.
///
/// Handles complex navigation, media previews (video/audio), secondary display
/// synchronization, and game metadata orchestration.
class SystemGamesList extends StatefulWidget {
  final SystemModel system;
  final FileProvider fileProvider;
  final String? initialRomPath;

  const SystemGamesList({
    super.key,
    required this.system,
    required this.fileProvider,
    this.initialRomPath,
  });

  @override
  State<SystemGamesList> createState() => _SystemGamesListState();
}

class _SystemGamesListState extends State<SystemGamesList> {
  static final _log = LoggerService.instance;
  static final _letterRegex = RegExp(r'[A-Z0-9]');

  // Dataset management.
  List<GameModel> _games = [];
  Map<GameModel, int> _gameIndexMap = {};
  GameModel? _selectedGame;

  // Navigation & State orchestration.
  bool _isLoading = true;
  bool _isLoadingGames = false; // Prevents redundant reload triggers.
  int _selectedGameIndex = 0;
  late GamepadNavigation
  _gamepadNav; // Unified controller/keyboard input handler.

  // Integration callbacks for GameDetailsCardList.
  VoidCallback? _refreshAchievementsCallback;

  // Overlay interaction delegates.
  bool Function()? _isAchievementsOpen;
  VoidCallback? _moveAchievementUp;
  VoidCallback? _moveAchievementDown;
  VoidCallback? _moveAchievementLeft;
  VoidCallback? _moveAchievementRight;
  VoidCallback? _triggerOverlayAction;
  VoidCallback? _secondaryOverlayAction; // Maps to RB (Scrape/Refresh).
  bool Function(bool isRight)?
  _tabNavigationAction; // Facilitates tab switching via bumpers.
  VoidCallback? _startActionCallback; // Maps to Start button.
  bool Function()? _isPlayingGameBlocked; // Validation for launch readiness.

  // Secondary display hardware management (OEM support).
  SecondaryDisplayState? _secondaryDisplayState;

  /// Drives the live RetroAchievements panel on the secondary display for the
  /// duration of a launched game (push at launch, poll during play, stop on
  /// return). Shared with the systems carousel/grid "Recent Games" launches.
  final SecondaryAchievementsController _achievementsController =
      SecondaryAchievementsController();

  bool _canPop = false;

  // View keys for scroll synchronization.
  final GlobalKey<GameListViewState> _gameListKey =
      GlobalKey<GameListViewState>();

  // Multimedia preview orchestration.
  Timer? _videoTimer;
  bool _showVideo = false;
  bool _isVideoLoading = false;
  static const Duration _videoDelay = Duration(
    milliseconds: 1500,
  ); // Debounce for video playback.
  bool _lastShowInfo = false; // Memoizes 'showGameInfo' config state.
  bool _isGameLaunching =
      false; // Critical flag to suppress media tasks during transitions.

  // Task orchestration timers.
  Timer? _saveDetectionTimer;
  Timer? _musicExtractionTimer;
  Timer? _fastNavEndTimer; // Detects the end of rapid scrolling.

  // Rapid navigation state.
  bool _isNavigatingFast = false;
  String? _currentLetter;
  DateTime? _lastNavTime;
  static const Duration _fastNavThreshold = Duration(milliseconds: 150);

  // Media controllers.
  VideoPlayerController? _videoController;

  // Scraping state.
  final Set<String> _scrapingGameRomnames = {};
  final Map<String, double> _scrapeProgress = {};

  // Localized metadata.
  String? _localizedDescription;

  // Resource providers.
  late FileProvider _fileProvider;

  // UI focus management.
  late final FocusNode _backButtonFocusNode;

  RetroAchievementsProvider get _retroAchievementsProvider =>
      context.read<RetroAchievementsProvider>();

  // Memoized providers for lifecycle management.
  late SqliteConfigProvider _configProvider;
  late SqliteDatabaseProvider _databaseProvider;

  // Cached theme-dependent colors for letter indicator — updated in didChangeDependencies.
  Color _letterIndicatorBg = Colors.black.withValues(alpha: 0.7);
  Color _letterIndicatorBorder = Colors.transparent;
  Color _letterIndicatorShadow = Colors.transparent;
  Color _letterIndicatorTextShadow = Colors.transparent;

  @override
  void initState() {
    super.initState();
    _fileProvider = widget.fileProvider;
    _backButtonFocusNode = FocusNode(skipTraversal: true);
    _loadGames();
    _initializeGamepad();

    // Attach persistent listeners to global providers.
    _databaseProvider = context.read<SqliteDatabaseProvider>();
    _databaseProvider.addListener(_onDatabaseUpdated);

    _configProvider = context.read<SqliteConfigProvider>();
    _configProvider.addListener(_onConfigChanged);

    _lastShowInfo = _configProvider.config.showGameInfo;

    MusicPlayerService().addListener(_onMusicPlayerStateChanged);

    if (Platform.isAndroid) {
      _secondaryDisplayState = SecondaryDisplayState.instance;
      _secondaryDisplayState!.addListener(_onSecondaryDisplayChanged);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final primary = Theme.of(context).colorScheme.primary;
    _letterIndicatorBg = Colors.black.withValues(alpha: 0.7);
    _letterIndicatorBorder = primary.withValues(alpha: 0.5);
    _letterIndicatorShadow = primary.withValues(alpha: 0.3);
    _letterIndicatorTextShadow = primary;
  }

  void _onSecondaryDisplayChanged() {
    if (mounted) {
      setState(() {});
      _updateMusicDucking();
    }
  }

  @override
  void dispose() {
    // Detach listeners before disposal.
    _configProvider.removeListener(_onConfigChanged);
    _databaseProvider.removeListener(_onDatabaseUpdated);
    MusicPlayerService().removeListener(_onMusicPlayerStateChanged);

    // Shared singleton — detach our listener, never dispose the instance.
    _secondaryDisplayState?.removeListener(_onSecondaryDisplayChanged);
    _achievementsController.dispose();

    _cleanupResources();
    _backButtonFocusNode.dispose();
    super.dispose();
  }

  /// Synchronizes UI state with global configuration changes.
  void _onConfigChanged() {
    if (!mounted) return;
    final configProvider = context.read<SqliteConfigProvider>();
    final newShowInfo = configProvider.config.showGameInfo;
    final gameViewMode = configProvider.config.gameViewMode;

    try {
      if (gameViewMode == 'grid' || gameViewMode == 'carousel') {
        _gamepadNav.deactivate();
      } else {
        _gamepadNav.activate();
      }
    } catch (_) {}

    if (newShowInfo != _lastShowInfo) {
      _lastShowInfo = newShowInfo;

      if (newShowInfo) {
        // Resume media preview if info overlay is enabled.
        if (_selectedGame != null &&
            !_showVideo &&
            _videoTimer == null &&
            !_isGameLaunching) {
          _startVideoTimer();
        }
      } else {
        // Immediate termination of media preview if info overlay is hidden.
        _resetVideoState();
      }

      if (_selectedGame != null) {
        _updateSecondaryDisplay(_selectedGame!);
      }
    }

    // Refresh audio ducking logic (e.g., when toggling video sound).
    _updateMusicDucking();
  }

  /// Triggers UI refresh upon music player state transitions.
  void _onMusicPlayerStateChanged() {
    if (!mounted ||
        widget.system.folderName != 'music' ||
        _selectedGame == null) {
      return;
    }

    _updateSecondaryDisplay(_selectedGame!);
  }

  void _onScrapeCurrentGame() async {
    final game = _selectedGame;
    if (game == null) return;
    final romname = game.romname;
    final romPath = game.romPath;
    if (romPath == null) return;
    if (_scrapingGameRomnames.contains(romname)) return;

    // Audible feedback when a scrape is initiated. The on-screen scrape
    // button plays this via its own onTap, but the Select shortcut routes
    // here directly, so play it here to keep both paths consistent.
    SfxService().playNavSound();

    // Claim the lock synchronously, before any await, so rapid repeated
    // presses (the scrape button or the Select shortcut) can't slip past the
    // guard above and queue duplicate scrapes for the same game.
    _scrapingGameRomnames.add(romname);
    _scrapeProgress[romname] = 0.0;
    setState(() {});

    // Resolve the actual system (not favorites virtual system).
    SystemModel targetSystem = widget.system;
    if ((widget.system.folderName == SystemFolderNames.all ||
            widget.system.folderName == SystemFolderNames.favorites) &&
        game.systemFolderName != null) {
      final original = await SystemRepository.getSystemByFolderName(
        game.systemFolderName!,
      );
      if (original != null) {
        targetSystem = original;
      }
    }

    final systemId = targetSystem.id;
    if (systemId == null) {
      _scrapingGameRomnames.remove(romname);
      _scrapeProgress.remove(romname);
      if (mounted) setState(() {});
      return;
    }

    ScreenScraperService.scrapeSingleGame(
          appSystemId: systemId,
          romName: game.romname,
          systemFolder: targetSystem.primaryFolderName,
          romPath: romPath,
          gameName: game.name,
          forceOverwrite: true,
          onProgress: (status, progress) {
            _scrapeProgress[romname] = progress;
            setState(() {});
          },
        )
        .then((result) async {
          final systemFolder = targetSystem.primaryFolderName;
          final imagesToEvict = [
            game.getScreenshotPath(systemFolder),
            game.getImagePath(systemFolder, 'wheels', widget.fileProvider),
            game.getImagePath(systemFolder, 'fanarts', widget.fileProvider),
            game.getImagePath(systemFolder, 'box2d', widget.fileProvider),
          ];
          for (final imagePath in imagesToEvict) {
            final imageFile = File(imagePath);
            if (await imageFile.exists()) {
              await FileImage(imageFile).evict();
            }
          }

          final updatedGame = await GameService.getGameDetails(
            targetSystem,
            romname,
          );
          if (mounted && updatedGame != null) {
            final gameIndex = _games.indexWhere((g) => g.romname == romname);
            if (gameIndex >= 0) {
              setState(() {
                _games[gameIndex] = updatedGame;
                if (_selectedGame?.romname == romname) {
                  _selectedGame = updatedGame;
                }
              });
              // Refresh the cached localized description so the scrape button
              // label flips from 'Scrape' to 'Rescrape' immediately (it keys
              // off whether a description is present).
              if (_selectedGame?.romname == romname) {
                _loadLocalizedDescription();
                // Push the freshly-scraped media to the secondary screen and
                // the main background right away. The main list rebuilds from
                // _selectedGame via setState, but the secondary window is a
                // separate engine fed only through _updateSecondaryDisplay —
                // without this it stays stale until the selection changes.
                _updateBackground(updatedGame);
                _updateSecondaryDisplay(updatedGame, forceMediaRefresh: true);
                _updateSecondaryDisplayVideo(updatedGame);
              }
            }
          }

          if (mounted) {
            AppNotification.showNotification(
              context,
              result['success'] == true
                  ? 'Scraping completed'
                  : 'Scraping failed: ${result['message']}',
              type: result['success'] == true
                  ? NotificationType.success
                  : NotificationType.error,
            );
          }
        })
        .whenComplete(() {
          _scrapingGameRomnames.remove(romname);
          _scrapeProgress.remove(romname);
          if (mounted) setState(() {});
        });
  }

  /// Responds to SQLite database updates by reloading the game list.
  void _onDatabaseUpdated() {
    if (mounted && !_isLoadingGames) {
      _loadGames();
    }
  }

  /// Terminates all active multimedia and background processing tasks.
  void _cleanupResources() {
    GamepadNavigationManager.popLayer('system_games_list');

    _videoTimer?.cancel();
    _saveDetectionTimer?.cancel();
    _musicExtractionTimer?.cancel();

    if (_videoController != null) {
      final controller = _videoController!;
      _videoController = null;
      try {
        controller.dispose();
      } catch (e) {
        _log.w('Error disposing video controller in cleanup: $e');
      }
    }

    _gamepadNav.dispose();

    // Force restore background music volume.
    MusicPlayerService().setDucked(false);
  }

  /// Bridge so `part` extension files (e.g. gamepad nav) can request a
  /// rebuild — [State.setState] is `@protected` and cannot be invoked from an
  /// extension. Behaviourally identical to calling `setState` directly.
  void rebuild(VoidCallback fn) => setState(fn);

  /// Hard reset of the video preview system.
  void _resetVideoState() {
    _videoTimer?.cancel();
    _videoTimer = null;

    if (_videoController != null) {
      final controller = _videoController!;
      _videoController = null;
      try {
        controller.dispose();
      } catch (e) {
        _log.w('Error disposing video controller in reset: $e');
      }
    }

    if (mounted) {
      setState(() {
        _showVideo = false;
        _isVideoLoading = false;
      });
    }
  }

  /// Graceful termination of video resources with state synchronization.
  void _stopVideoAndCleanup() {
    _videoTimer?.cancel();
    _videoTimer = null;

    if (_videoController != null) {
      final controller = _videoController!;
      _videoController = null;
      try {
        controller.dispose();
      } catch (e) {
        _log.w('Error disposing video controller: $e');
      }
    }

    if (mounted) {
      setState(() {
        _showVideo = false;
        _isVideoLoading = false;
      });
    }
    _updateMusicDucking();
  }

  /// Frees maximum RAM before handing off to the emulator.
  /// Play time tracking continues unaffected in GameService.
  void _freeMemoryForGameplay() {
    // Clear all cached images — system backgrounds, logos, screenshots.
    imageCache.clear();
    imageCache.clearLiveImages();

    // Release game list from memory. Reloaded on game close.
    setState(() {
      _games = [];
      _gameIndexMap = {};
    });

    // Clear the system background image provider.
    if (mounted) {
      context.read<SystemBackgroundProvider>().clear();
    }
  }

  /// Core logic for updating selection and managing rapid-scrolling UI state.
  void _updateSelectedGame(int newIndex) {
    _resetVideoState();

    final now = DateTime.now();
    bool isFast = false;
    if (_lastNavTime != null) {
      final delta = now.difference(_lastNavTime!);
      if (delta < _fastNavThreshold) {
        isFast = true;
      }
    }
    _lastNavTime = now;

    // Resolve current alphabetical letter for navigation overlays.
    final game = _games[newIndex];
    String? letter;
    final displayName = game.name.isNotEmpty ? game.name : game.romname;
    if (displayName.isNotEmpty) {
      String cleanName = displayName.trim().toUpperCase();
      if (cleanName.startsWith('THE ')) cleanName = cleanName.substring(4);

      if (cleanName.isNotEmpty) {
        final firstChar = cleanName[0];
        if (_letterRegex.hasMatch(firstChar)) {
          letter = firstChar;
        } else {
          letter = '#';
        }
      }
    }

    setState(() {
      _selectedGameIndex = newIndex;
      _selectedGame = game;
      _isNavigatingFast = isFast;
      _currentLetter = letter;
    });

    // Debounce rapid navigation end to resume heavy resource loading.
    _fastNavEndTimer?.cancel();
    _fastNavEndTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        setState(() {
          _isNavigatingFast = false;
        });
        _performBackgroundOperationsForSelectedGame(force: true);

        Timer(const Duration(milliseconds: 200), () {
          if (mounted && !_isNavigatingFast) {
            setState(() => _currentLetter = null);
          }
        });
      }
    });

    _performBackgroundOperationsForSelectedGame();
  }

  /// Orchestrates background tasks triggered by game selection changes.
  void _performBackgroundOperationsForSelectedGame({bool force = false}) {
    if (_selectedGame == null || !mounted) return;

    // Suppress expensive operations (video, isolates) during rapid scrolling.
    if (_isNavigatingFast && !force) {
      _updateBackground(_selectedGame!);
      _updateSecondaryDisplay(_selectedGame!);
      return;
    }

    _detectGameSavesForSelectedGame();
    _loadLocalizedDescription();
    _startVideoTimer();
    _updateBackground(_selectedGame!);
    _updateSecondaryDisplay(_selectedGame!);
    _updateMusicDucking();
  }

  /// Synchronizes selection metadata and assets with secondary hardware displays.
  ///
  /// [forceMediaRefresh] forces a push even when every media path is unchanged
  /// and bumps [SecondaryDisplayStateData.mediaRevision]. Use it after a
  /// re-scrape (forceOverwrite) rewrites the art in place: the paths stay the
  /// same, so the dedup below would otherwise skip the update and the secondary
  /// engine would keep showing the stale cached bitmap.
  Future<void> _updateSecondaryDisplay(
    GameModel game, {
    bool forceMediaRefresh = false,
  }) async {
    if (_secondaryDisplayState == null || _isNavigatingBack) return;

    final systemFolderName =
        (widget.system.folderName == 'all' ||
                widget.system.folderName == SystemFolderNames.favorites) &&
            game.systemFolderName != null
        ? game.systemFolderName!
        : widget.system.primaryFolderName;

    // Media resolution hierarchy.
    final screenshotPath = game.getScreenshotPath(
      systemFolderName,
      _fileProvider,
    );

    final fanartPath = game.getImagePath(
      systemFolderName,
      'fanarts',
      _fileProvider,
    );

    final wheelPath = game.getImagePath(
      systemFolderName,
      'wheels',
      _fileProvider,
    );

    final videoPath = _getVideoPath(game);
    final videoExists = await _fileProvider.fileExists(videoPath);

    final configProvider = mounted
        ? context.read<SqliteConfigProvider>()
        : null;
    final isVideoMuted = !configProvider!.config.videoSound;
    final isScraperLoggedIn = await ScreenScraperService.hasSavedCredentials();

    final isMusicSystem = widget.system.folderName == 'music';

    // State optimization: Skip updates if metadata remains identical. A forced
    // media refresh (post re-scrape) always pushes — the paths are unchanged
    // but their bytes are not, so the secondary engine must be told to re-decode.
    final currentState = _secondaryDisplayState?.value;
    final bool shouldUpdate =
        forceMediaRefresh ||
        currentState == null ||
        currentState.systemName != widget.system.realName ||
        currentState.gameId !=
            (isMusicSystem
                ? MusicPlayerService().activeTrack?.romPath
                : game.romPath) ||
        currentState.gameFanart !=
            (isMusicSystem
                ? null
                : (File(fanartPath).existsSync() ? fanartPath : null)) ||
        currentState.gameScreenshot !=
            (isMusicSystem
                ? null
                : (File(screenshotPath).existsSync()
                      ? screenshotPath
                      : null)) ||
        currentState.gameVideo !=
            (isMusicSystem ? null : (videoExists ? videoPath : null)) ||
        currentState.gameWheel !=
            (isMusicSystem
                ? null
                : (File(wheelPath).existsSync() ? wheelPath : null)) ||
        currentState.isVideoMuted != isVideoMuted ||
        currentState.isGameLaunching != _isGameLaunching;

    if (shouldUpdate && !_isNavigatingBack) {
      final bool hasFanart = !isMusicSystem && File(fanartPath).existsSync();
      final bool hasScreenshot =
          !isMusicSystem && File(screenshotPath).existsSync();
      final bool hasWheel = !isMusicSystem && File(wheelPath).existsSync();

      // ignore: unawaited_futures
      _secondaryDisplayState?.updateState(
        systemName: widget.system.realName,
        gameFanart: hasFanart ? fanartPath : null,
        gameScreenshot: hasScreenshot ? screenshotPath : null,
        clearFanart: !hasFanart,
        clearScreenshot: !hasScreenshot,
        gameWheel: hasWheel ? wheelPath : null,
        clearWheel: !hasWheel,
        gameVideo: null, // Reset video state during active scrolling.
        clearVideo: true,
        gameImageBytes: null,
        clearImageBytes: isMusicSystem
            ? (MusicPlayerService().activeTrack == null)
            : true,
        isGameSelected: true,
        isVideoMuted: isVideoMuted,
        backgroundColor: mounted
            ? Theme.of(context).scaffoldBackgroundColor.toARGB32()
            : null,
        isGameLaunching: _isGameLaunching,
        gameId: isMusicSystem
            ? MusicPlayerService().activeTrack?.romPath
            : game.romPath,
        isScraperLoggedIn: isScraperLoggedIn,
        // Bump the revision on a forced refresh so the secondary engine evicts
        // its now-stale cached bitmaps and re-decodes the same paths from disk.
        mediaRevision: forceMediaRefresh
            ? (currentState?.mediaRevision ?? 0) + 1
            : null,
        // Panel is shown only by the launch push / live poll; browsing and
        // returning from a game hide it (it fades out on the secondary screen).
        showAchievementPanel: false,
      );
    }

    _updateMusicDucking();

    // Special handling for cover art extraction in Music mode.
    if (isMusicSystem) {
      final musicService = MusicPlayerService();
      final activeTrack = musicService.activeTrack;

      if (activeTrack != null) {
        final String? activeRomPath = activeTrack.romPath;

        if (activeRomPath != null) {
          final currentBytes = _secondaryDisplayState?.value?.gameImageBytes;
          final activeBytes = musicService.activePicture;

          if (activeBytes != null &&
              !listEquals(activeBytes, currentBytes) &&
              !_isNavigatingBack) {
            // ignore: unawaited_futures
            _secondaryDisplayState?.updateState(
              gameImageBytes: activeBytes,
              gameId: activeRomPath,
            );
          } else if (activeBytes == null) {
            _musicExtractionTimer?.cancel();
            _musicExtractionTimer = Timer(
              const Duration(milliseconds: 250),
              () {
                musicService.extractPicture(activeRomPath).then((
                  Uint8List? bytes,
                ) {
                  if (bytes != null && mounted) {
                    final latestBytes =
                        _secondaryDisplayState?.value?.gameImageBytes;
                    if (!listEquals(bytes, latestBytes) && !_isNavigatingBack) {
                      _secondaryDisplayState?.updateState(
                        gameImageBytes: bytes,
                        gameId: activeRomPath,
                      );
                    }
                  }
                });
              },
            );
          }
        }
      } else {
        _secondaryDisplayState?.updateState(
          gameImageBytes: null,
          clearImageBytes: true,
        );
      }
    }
  }

  /// Pushes specific video path updates to the secondary screen.
  Future<void> _updateSecondaryDisplayVideo(GameModel game) async {
    if (_secondaryDisplayState == null ||
        _isNavigatingBack ||
        _selectedGame != game) {
      return;
    }

    final videoPath = _getVideoPath(game);
    final videoExists = await _fileProvider.fileExists(videoPath);

    if (videoExists && !_isNavigatingBack && _selectedGame == game) {
      // ignore: unawaited_futures
      _secondaryDisplayState?.updateState(gameVideo: videoPath);
      _updateMusicDucking();
    }
  }

  /// Dynamically adjusts background music volume to prevent audio conflicts with video previews.
  void _updateMusicDucking() {
    if (!mounted) return;

    final config = context.read<SqliteConfigProvider>().config;

    // Suppress ducking within the Music Player system itself.
    if (widget.system.folderName == 'music') return;

    if (!config.videoSound) {
      MusicPlayerService().setDucked(false);
      return;
    }

    // Condition 2: Video is actually playing on primary
    bool primaryIsPlaying = _showVideo && !_isGameLaunching;

    // Condition 3: Secondary screen is active and actually playing a video
    final secondaryState = _secondaryDisplayState?.value;
    bool secondaryIsPlaying =
        (secondaryState?.isSecondaryActive ?? false) &&
        (secondaryState?.gameVideo != null);

    final shouldDuck = primaryIsPlaying || secondaryIsPlaying;
    MusicPlayerService().setDucked(shouldDuck);
  }

  void _updateBackground(GameModel game) {
    if (!mounted ||
        widget.system.folderName == 'all' ||
        widget.system.folderName == SystemFolderNames.favorites) {
      return;
    }

    final systemFolderName = widget.system.primaryFolderName;

    // Resolve game background: Prioritize high-resolution fanart, fallback to screenshot, then system default.
    String imagePath = game.getImagePath(
      systemFolderName,
      'fanarts',
      _fileProvider,
    );
    bool exists = File(imagePath).existsSync();

    if (!exists) {
      imagePath = game.getScreenshotPath(systemFolderName, _fileProvider);
      exists = File(imagePath).existsSync();
    }

    final ImageProvider imageProvider;
    if (exists) {
      imageProvider = FileImage(File(imagePath));
    } else {
      // Hardware-specific fallback if no game-specific art is resolved.
      final sysId =
          (widget.system.folderName == 'all' ||
                  widget.system.folderName == SystemFolderNames.favorites) &&
              game.systemFolderName != null
          ? game.systemFolderName!
          : widget.system.id;
      final path =
          'assets/images/logos/$sysId.webp'; // Correcting to logo fallback for grid consistency.
      imageProvider = AssetImage(path);
      imagePath = path;
    }

    context.read<SystemBackgroundProvider>().updateImage(
      imageProvider,
      imagePath: imagePath,
    );
  }

  /// Initiates game save detection with a 600ms debounce to optimize rapid scrolling.
  void _detectGameSavesForSelectedGame() {
    _saveDetectionTimer?.cancel();

    _saveDetectionTimer = Timer(const Duration(milliseconds: 600), () async {
      if (_selectedGame == null || !mounted) return;

      try {
        final syncProvider = context.read<SyncManager>().active!;
        await syncProvider.detectGameSaveFiles(_selectedGame!);
      } catch (e) {
        _log.e('Game save detection failed: $e');
      }
    });
  }

  /// Retrieves localized game descriptions directly from the SQLite database.
  void _loadLocalizedDescription() async {
    if (_selectedGame == null) return;

    try {
      String? systemId;

      // In 'Global Library' mode, resolve the game's native hardware system ID.
      if ((widget.system.folderName == 'all' ||
              widget.system.folderName == SystemFolderNames.favorites) &&
          _selectedGame!.systemFolderName != null) {
        final originalSystem = await SystemRepository.getSystemByFolderName(
          _selectedGame!.systemFolderName!,
        );
        systemId = originalSystem?.id;
      } else {
        systemId = widget.system.id;
      }

      if (systemId == null) {
        if (mounted) {
          setState(() {
            _localizedDescription = null;
          });
        }
        return;
      }

      final description = await GameRepository.getLocalizedDescription(
        _selectedGame!.romname,
        systemId,
      );

      if (mounted &&
          _selectedGame != null &&
          _selectedGame!.romname == _selectedGame!.romname) {
        setState(() {
          _localizedDescription = description;
        });
      }
    } catch (e) {
      _log.e('Localized description loading failed: $e');
      if (mounted) {
        setState(() {
          _localizedDescription = null;
        });
      }
    }
  }

  bool _isNavigatingBack = false;

  /// Orchestrates a graceful exit from the game list, synchronizing state with previous screens.
  Future<void> _goBack() async {
    if (_isNavigatingBack) {
      return;
    }

    _isNavigatingBack = true;

    // Immediate resource termination.
    _stopVideoAndCleanup();

    // Release current input layers.
    GamepadNavigationManager.popLayer('games_grid');
    GamepadNavigationManager.popLayer('system_games_list');

    // Restore secondary display to original system branding. Resolve the logo
    // and background the same way the systems grid does (custom → active-theme
    // → bundled asset, themed background when present) so themed systems don't
    // flash the default logo here before the grid re-asserts its state on pop.
    final configProvider = context.read<SqliteConfigProvider>();
    final folder = widget.system.primaryFolderName;

    final String? customLogo = widget.system.customLogoPath?.isNotEmpty == true
        ? widget.system.customLogoPath
        : null;
    final systemLogo = customLogo ?? 'assets/images/logos/$folder.webp';
    final bool isLogoAsset = customLogo == null;

    final neoAssets = context.read<NeoAssetsProvider>();
    final String? customBg = widget.system.customBackgroundPath;
    final bool hasCustomBg = customBg != null && customBg.isNotEmpty;
    final String? themeBg = hasCustomBg
        ? null
        : neoAssets.getBackgroundForSystemSync(folder);
    final String? systemBackground = hasCustomBg ? customBg : themeBg;

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final isOled = themeProvider.isOled;

    // ignore: unawaited_futures
    _secondaryDisplayState?.updateState(
      systemName: widget.system.realName,
      isGameSelected: false,
      isVideoMuted: !configProvider.config.videoSound,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor.toARGB32(),
      systemLogo: systemLogo,
      isLogoAsset: isLogoAsset,
      systemBackground: systemBackground,
      clearSystemBackground: systemBackground == null,
      isBackgroundAsset: false,
      useShader: systemBackground == null,
      shaderColor1: widget.system.color1AsColor?.toARGB32(),
      shaderColor2: widget.system.color2AsColor?.toARGB32(),
      useFluidShader: false,
      isOled: isOled,
      clearFanart: true,
      clearScreenshot: true,
      clearWheel: true,
      clearVideo: true,
      clearImageBytes: true,
      clearGameId: true,
    );

    setState(() {
      _canPop = true;
    });

    // Defer navigation to the next frame to ensure PopScope validates [_canPop].
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.of(context).pop();

        // CRITICAL: Re-establish input focus for the previous system screen layers.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          GamepadNavigationManager.reactivate();

          if (mounted) {
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) {
                _isNavigatingBack = false;
              }
            });
          }
        });
      }
    });
  }

  /// Restores UI state and input focus after an external emulator process terminates.
  /// Resolves the effective system folder name for a game, accounting for the
  /// aggregate "all"/favorites views where each game carries its own system.
  String _resolveSystemFolderName(GameModel game) {
    return (widget.system.folderName == 'all' ||
                widget.system.folderName == SystemFolderNames.favorites) &&
            game.systemFolderName != null
        ? game.systemFolderName!
        : widget.system.primaryFolderName;
  }

  /// Resolves and pushes the launched game's achievement panel to the secondary
  /// display, then keeps it live for the session. Delegates to the shared
  /// [SecondaryAchievementsController]; no-op when there is no active secondary
  /// display, RA is disconnected, or the game has no achievement set.
  Future<void> _pushAchievementsForLaunch(GameModel game) {
    final systemFolderName = _resolveSystemFolderName(game);
    return _achievementsController.pushForLaunch(
      state: _secondaryDisplayState,
      provider: _retroAchievementsProvider,
      game: game,
      systemFolderName: systemFolderName,
      boxartPath: SecondaryAchievementsController.resolveBoxart(
        game,
        systemFolderName,
        _fileProvider,
      ),
    );
  }

  void _reactivateGamepadNavigation() async {
    if (!mounted) return;

    // Host re-pushes full game art below (hidePanel: false), which carries the
    // panel-off flag, so the panel fades back to the art on return.
    _achievementsController.stop();

    if (mounted) {
      setState(() {
        _isGameLaunching = false;
      });
      // Returning from the game: hide the panel so it fades back to game art.
      // Any unlocks were already surfaced live during play.
      if (_selectedGame != null) _updateSecondaryDisplay(_selectedGame!);
    }

    GamepadNavigationManager.reactivate();

    // Reload games list (was cleared to free RAM during gameplay).
    try {
      final updatedGames = await GameService.loadGamesForSystem(widget.system);
      if (!mounted) return;

      final previousRomname = _selectedGame?.romname;
      final gameIndex = previousRomname != null
          ? updatedGames.indexWhere((g) => g.romname == previousRomname)
          : -1;

      setState(() {
        _games = updatedGames;
        _gameIndexMap = {
          for (int i = 0; i < updatedGames.length; i++) updatedGames[i]: i,
        };
        if (gameIndex != -1) {
          _selectedGame = updatedGames[gameIndex];
          _selectedGameIndex = gameIndex;
        }
      });
      _databaseProvider.refresh();
    } catch (e) {
      _log.e('Error refreshing game data after gameplay: $e');
    }

    // Defer to after the games-list reload settles and the details card has
    // re-registered its callback, otherwise this fires against the old/unmounted
    // card and no-ops — which is why a manual refresh was previously needed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshAchievementsCallback?.call();
    });

    // Trigger sync after returning from game so local save gets uploaded.
    if (_selectedGame != null && mounted) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      try {
        final syncProvider = context.read<SyncManager>().active!;
        await syncProvider.detectGameSaveFiles(_selectedGame!);
      } catch (e) {
        _log.e('Post-game save sync failed: $e');
      }
    }
  }

  /// Toggles the 'favorite' status for the selected game and re-sorts the list.
  Future<void> _toggleFavorite() async {
    if (_selectedGame == null) return;

    if (widget.system.folderName == 'music') {
      try {
        final configProvider = context.read<SqliteConfigProvider>();
        await GameService.toggleFavorite(_selectedGame!);
        if (!mounted) return;
        await configProvider.refreshDetectedSystems();

        setState(() {
          final gameIndex = _games.indexWhere(
            (g) => g.romname == _selectedGame!.romname,
          );
          if (gameIndex != -1) {
            final currentFavorite = _games[gameIndex].isFavorite ?? false;
            _games[gameIndex] = _games[gameIndex].copyWith(
              isFavorite: !currentFavorite,
            );
            _selectedGame = _games[gameIndex];
          }
        });

        _reorderGamesListKeepingVisualPosition();

        if (!mounted) return;
        AppNotification.showNotification(
          context,
          AppLocale.favoriteUpdated.getString(context),
          type: NotificationType.success,
        );
      } catch (e) {
        _log.e('Error toggling music favorite: $e');
      }
      return;
    }

    try {
      final configProvider = context.read<SqliteConfigProvider>();
      await GameService.toggleFavorite(_selectedGame!);

      if (!mounted) return;
      await configProvider.refreshDetectedSystems();

      setState(() {
        final gameIndex = _games.indexWhere(
          (game) => game.romname == _selectedGame!.romname,
        );
        if (gameIndex != -1) {
          final currentFavorite = _games[gameIndex].isFavorite ?? false;
          _games[gameIndex] = _games[gameIndex].copyWith(
            isFavorite: !currentFavorite,
          );
          _selectedGame = _games[gameIndex];
        }
      });

      _reorderGamesListKeepingVisualPosition();

      if (!mounted) return;
      AppNotification.showNotification(
        context,
        AppLocale.favoriteUpdated.getString(context),
        type: NotificationType.success,
      );
    } catch (error) {
      if (!mounted) return;
      _log.e('Error toggling favorite: $error');
      if (!mounted) return;
      AppNotification.showNotification(
        context,
        AppLocale.errorUpdatingFavorite.getString(context),
        type: NotificationType.error,
      );
    }
  }

  /// Re-sorts the game collection (Favorites first, then Alphabetical) while
  /// preserving the user's current scroll/focus index for a seamless experience.
  void _reorderGamesListKeepingVisualPosition() {
    if (_selectedGame == null) return;

    final oldIndex = _selectedGameIndex;

    setState(() {
      final sortedGames = List<GameModel>.from(_games);

      sortedGames.sort((a, b) {
        if (a.isFavorite == true && b.isFavorite != true) return -1;
        if (a.isFavorite != true && b.isFavorite == true) return 1;
        return a.name.compareTo(b.name);
      });

      _games = sortedGames;
      _gameIndexMap = {for (int i = 0; i < _games.length; i++) _games[i]: i};

      if (oldIndex >= 0 && oldIndex < _games.length) {
        _selectedGameIndex = oldIndex;
        _selectedGame = _games[oldIndex];
      } else if (_games.isNotEmpty) {
        _selectedGameIndex = 0;
        _selectedGame = _games.first;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToSelectedItem();
      }
    });
  }

  /// Sorts the list and re-anchors focus to a specific ROM.
  /// Primarily used after scraping to follow a game to its new alphabetical position.
  void _reorderGamesListFollowingGame(String romname) {
    setState(() {
      final sortedGames = List<GameModel>.from(_games);
      sortedGames.sort((a, b) {
        if (a.isFavorite == true && b.isFavorite != true) return -1;
        if (a.isFavorite != true && b.isFavorite == true) return 1;
        return a.name.compareTo(b.name);
      });
      _games = sortedGames;
      _gameIndexMap = {for (int i = 0; i < _games.length; i++) _games[i]: i};

      final newIndex = _games.indexWhere((g) => g.romname == romname);
      if (newIndex != -1) {
        _selectedGameIndex = newIndex;
        _selectedGame = _games[newIndex];
      } else if (_games.isNotEmpty) {
        _selectedGameIndex = 0;
        _selectedGame = _games.first;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToSelectedItem();
    });
  }

  /// Orchestrates the complex sequence for launching a game through an external emulator.
  Future<void> _selectCurrentGame() async {
    if (_selectedGame == null) return;

    // Special handling for the Integrated Music Player.
    if (widget.system.folderName == 'music') {
      final service = MusicPlayerService();
      final isPlaying = service.isPlaying;
      final isHearingCurrent =
          service.activeTrack?.romPath == _selectedGame!.romPath;

      if (isPlaying && isHearingCurrent) {
        service.pause();
      } else {
        if (isHearingCurrent && service.isStarted) {
          service.resume();
        } else {
          service.start(index: _selectedGameIndex);
        }
      }
      return;
    }

    // Guard: Prevent launch if an overlay (e.g., Settings) is blocking interaction.
    if (_isPlayingGameBlocked != null && _isPlayingGameBlocked!()) {
      _triggerOverlayAction?.call();
      return;
    }

    setState(() => _isGameLaunching = true);

    // Resolve targeted hardware system for the launch.
    SystemModel systemToLaunch = widget.system;

    if ((widget.system.folderName == 'all' ||
            widget.system.folderName == SystemFolderNames.favorites) &&
        _selectedGame!.systemFolderName != null) {
      final availableSystems = context
          .read<SqliteConfigProvider>()
          .availableSystems;
      final realSystem = availableSystems.firstWhere(
        (sys) => sys.folderName == _selectedGame!.systemFolderName,
        orElse: () {
          _log.w(
            'Could not find system for folder: ${_selectedGame!.systemFolderName}',
          );
          return widget.system;
        },
      );

      systemToLaunch = realSystem;
    }

    // Resource termination and UI synchronization prior to process handoff.
    _stopVideoAndCleanup();
    // NOTE: do NOT push a separate _updateSecondaryDisplay here. The game's
    // media is already in the shared state from browsing, and a separate launch
    // snapshot (carrying nowPlayingActive=false + isGameLaunching=true) can be
    // delivered to the secondary engine AFTER the Now Playing push below and
    // clobber it — the cross-engine transport gives no ordering guarantee. The
    // launch push (_pushAchievementsForLaunch) now carries isGameLaunching
    // itself, so it is the single authoritative launch write.
    if (!mounted) return;

    // Push the in-game RetroAchievements panel. Fired without awaiting so it
    // never blocks the emulator handoff; it lands during launchGameWithDialog's
    // ~2s foreground window, giving the secondary engine time to paint the
    // panel and load badge art before the activity is backgrounded.
    // ignore: unawaited_futures
    _pushAchievementsForLaunch(_selectedGame!);

    // CRITICAL: Deactivate local input to avoid conflicts with external processes.
    _gamepadNav.deactivate();

    // Free maximum RAM before handing off to the emulator.
    _freeMemoryForGameplay();

    try {
      if (!mounted) return;

      final syncProvider = context.read<SyncManager>().active!;
      final selectedGame = _selectedGame!;

      await launchGameWithDialog(
        context: context,
        game: selectedGame,
        system: systemToLaunch,
        fileProvider: _fileProvider,
        syncProvider: syncProvider,
        onGameClosed: _reactivateGamepadNavigation,
        onLaunchFailed: (ctx, result) async {
          // Restore memory on failed launch.
          if (mounted) _loadGames();
          _log.e('SystemGamesList: Game launch failed');
          if (mounted && _isGameLaunching) {
            setState(() => _isGameLaunching = false);
          }
          await showDialog(
            context: ctx,
            builder: (BuildContext context) {
              return Focus(
                autofocus: true,
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    if (event.logicalKey == LogicalKeyboardKey.escape ||
                        event.logicalKey == LogicalKeyboardKey.backspace ||
                        event.logicalKey == LogicalKeyboardKey.enter) {
                      Navigator.of(context).pop();
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: AlertDialog(
                  backgroundColor: Colors.grey[900],
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16.r),
                    side: BorderSide(
                      color: Colors.red.withValues(alpha: 0.5),
                      width: 2.r,
                    ),
                  ),
                  title: Row(
                    children: [
                      Icon(
                        Symbols.error_outline_rounded,
                        color: Colors.red[400],
                        size: 32.r,
                      ),
                      SizedBox(width: 12.r),
                      Expanded(
                        child: Text(
                          AppLocale.launchGameFailed.getString(context),
                          style: TextStyle(color: Colors.white, fontSize: 20.r),
                        ),
                      ),
                    ],
                  ),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocale.unableToLaunch
                              .getString(context)
                              .replaceFirst('{name}', selectedGame.name),
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 16.r,
                          ),
                        ),
                        SizedBox(height: 16.r),
                        Container(
                          width: double.maxFinite,
                          padding: EdgeInsets.all(12.r),
                          decoration: BoxDecoration(
                            color: Colors.red[900]?.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(
                              color: Colors.red[700]!,
                              width: 1.r,
                            ),
                          ),
                          child: Text(
                            result.errorMessage ??
                                AppLocale.unknownError.getString(context),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.red[300],
                              fontSize: 14.r,
                            ),
                          ),
                        ),
                        if (result.errorDetails != null &&
                            result.errorDetails!.isNotEmpty) ...[
                          SizedBox(height: 16.r),
                          Text(
                            AppLocale.technicalDetails.getString(context),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[400],
                              fontSize: 13.r,
                            ),
                          ),
                          SizedBox(height: 8.r),
                          Container(
                            width: double.maxFinite,
                            padding: EdgeInsets.all(12.r),
                            decoration: BoxDecoration(
                              color: Colors.grey[850],
                              borderRadius: BorderRadius.circular(8.r),
                              border: Border.all(
                                color: Colors.grey[700]!,
                                width: 1.r,
                              ),
                            ),
                            child: Text(
                              result.errorDetails!,
                              style: TextStyle(
                                fontSize: 12.r,
                                fontFamily: 'monospace',
                                color: Colors.grey[300],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(
                      autofocus: true,
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.red[700],
                        padding: EdgeInsets.symmetric(
                          horizontal: 24.r,
                          vertical: 12.r,
                        ),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                        AppLocale.ok.getString(context),
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
          if (mounted) _gamepadNav.activate();
        },
      );
    } catch (error) {
      if (!mounted) return;

      if (mounted && _isGameLaunching) {
        Navigator.of(context).pop();
        setState(() {
          _isGameLaunching = false;
        });
      }

      _log.e('Error launching game: $error');

      await showDialog(
        context: context,
        builder: (BuildContext context) {
          return Focus(
            autofocus: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent) {
                if (event.logicalKey == LogicalKeyboardKey.escape ||
                    event.logicalKey == LogicalKeyboardKey.backspace ||
                    event.logicalKey == LogicalKeyboardKey.enter) {
                  Navigator.of(context).pop();
                  return KeyEventResult.handled;
                }
              }
              return KeyEventResult.ignored;
            },
            child: AlertDialog(
              backgroundColor: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16.r),
                side: BorderSide(
                  color: Colors.orange.withValues(alpha: 0.5),
                  width: 2.r,
                ),
              ),
              title: Row(
                children: [
                  Icon(
                    Symbols.warning_amber_rounded,
                    color: Colors.orange[400],
                    size: 32,
                  ),
                  SizedBox(width: 12.r),
                  Expanded(
                    child: Text(
                      AppLocale.launchError.getString(context),
                      style: TextStyle(color: Colors.white, fontSize: 20.r),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocale.unexpectedLaunchError
                          .getString(context)
                          .replaceFirst('{name}', _selectedGame!.name),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 15.r,
                      ),
                    ),
                    SizedBox(height: 16.r),
                    Text(
                      'Technical Details:',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[400],
                        fontSize: 13.r,
                      ),
                    ),
                    SizedBox(height: 8.r),
                    Container(
                      width: double.maxFinite,
                      padding: EdgeInsets.all(12.r),
                      decoration: BoxDecoration(
                        color: Colors.grey[850],
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(
                          color: Colors.grey[700]!,
                          width: 1.r,
                        ),
                      ),
                      child: Text(
                        error.toString(),
                        style: TextStyle(
                          fontSize: 12.r,
                          fontFamily: 'monospace',
                          color: Colors.orange[200],
                        ),
                      ),
                    ),
                    SizedBox(height: 16.r),
                    Text(
                      AppLocale.tryAgainGameConfig.getString(context),
                      style: TextStyle(fontSize: 12.r, color: Colors.grey[400]),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  autofocus: true,
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.orange[700],
                    padding: EdgeInsets.symmetric(
                      horizontal: 24.r,
                      vertical: 12.r,
                    ),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    AppLocale.ok.getString(context),
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );

      if (mounted) {
        _gamepadNav.activate();
      }
    }
  }

  /// Presents a 'Random Game' picker to the user.
  void _showRandomGameDialog() {
    if (_games.isEmpty) {
      return;
    }

    // Push a manager layer to deactivate the current active gamepad layer
    // (games_grid / games_carousel / system_games_list) so the random dialog
    // can capture back input without it leaking through to the parent.
    GamepadNavigationManager.pushLayer(
      'random_dialog',
      onActivate: () {},
      onDeactivate: () {},
    );

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return RandomGameDialog(
          games: _games,
          systemFolderName: widget.system.primaryFolderName,
          systemRealName: widget.system.realName,
          fileProvider: _fileProvider,
          onPlayGame: (selectedGame) {
            final gameIndex = _games.indexWhere(
              (game) => game.romname == selectedGame.romname,
            );
            if (gameIndex != -1) {
              setState(() {
                _selectedGameIndex = gameIndex;
                _selectedGame = _games[gameIndex];
              });

              _scrollToSelectedItem();

              // Ejecutar el juego después de un pequeño delay
              Future.delayed(const Duration(seconds: 1), () {
                if (mounted) {
                  _selectCurrentGame();
                }
              });
            }
          },
        );
      },
    ).then((_) async {
      // Wait a bit to prevent the button press from being processed twice
      await Future.delayed(const Duration(milliseconds: 100));
      if (mounted) {
        // Pop the dialog layer to reactivate the previous gamepad layer.
        GamepadNavigationManager.popLayer('random_dialog');
      }
    });
  }

  Future<void> _loadGames() async {
    if (!mounted || _isLoadingGames) return;
    _isLoadingGames = true;

    final isInitialLoad = _games.isEmpty;
    if (isInitialLoad) {
      setState(() => _isLoading = true);
    }

    try {
      final games = await GameService.loadGamesForSystem(widget.system);
      if (!mounted) return;

      _log.i(
        'SystemGamesList: Loaded ${games.length} games for ${widget.system.folderName}',
      );
      if (widget.system.folderName == 'music' && games.isNotEmpty) {
        _log.i(
          'SystemGamesList: First 3 music tracks: ${games.take(3).map((g) => g.name).toList()}',
        );
      }
      setState(() {
        _games = games;
        _gameIndexMap = {for (int i = 0; i < games.length; i++) games[i]: i};

        // Music system specialization: Anchor initial focus to the currently active track.
        if (widget.system.folderName == 'music') {
          final musicService = MusicPlayerService();
          if (musicService.isStarted && musicService.currentTrack != null) {
            final playingTrackPath = musicService.currentTrack?.romPath;
            final playingIndex = games.indexWhere(
              (g) => g.romPath == playingTrackPath,
            );

            if (playingIndex != -1) {
              _selectedGameIndex = playingIndex;
              _selectedGame = games[playingIndex];
              _log.i(
                'SystemGamesList: Initial focus set to playing track at index $playingIndex',
              );
            }
          }
        }

        if (widget.initialRomPath != null &&
            widget.initialRomPath!.isNotEmpty) {
          final initialIndex = games.indexWhere(
            (game) => game.romPath == widget.initialRomPath,
          );
          if (initialIndex != -1) {
            _selectedGameIndex = initialIndex;
            _selectedGame = games[initialIndex];
          } else {
            _selectedGameIndex = 0;
            _selectedGame = games.isNotEmpty ? games.first : null;
          }
        } else if (_selectedGame != null &&
            widget.system.folderName != 'music') {
          // Persistent Selection Logic: Retain current index if the game still exists post-reload.
          final selectedIndex = games.indexWhere(
            (game) => game.romname == _selectedGame!.romname,
          );
          if (selectedIndex != -1) {
            _selectedGameIndex = selectedIndex;
            _selectedGame = games[selectedIndex];
          } else {
            _selectedGameIndex = 0;
            _selectedGame = games.isNotEmpty ? games.first : null;
          }
        } else if (_selectedGame == null) {
          _selectedGameIndex = 0;
          _selectedGame = games.isNotEmpty ? games.first : null;
        }
        _isLoading = false;
      });

      // Trigger deferred media and background tasks after initial UI render.
      if (_selectedGame != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startVideoTimer();
          _performBackgroundOperationsForSelectedGame();
        });
      }
    } catch (e) {
      _log.e('Error loading games: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
        _isLoadingGames = false;
      }
    }
  }

  /// Selects a game via interaction (touch or click) and triggers resource resolution.
  Future<void> _selectGame(GameModel game) async {
    final index = _gameIndexMap[game] ?? _games.indexOf(game);
    if (index != -1) {
      _resetVideoState();
      setState(() {
        _selectedGameIndex = index;
        _selectedGame = game;
      });
      _scrollToSelectedItem();
      _performBackgroundOperationsForSelectedGame();
    }
  }

  /// Centers the currently selected item within the viewport.
  void _scrollToSelectedItem() {
    _gameListKey.currentState?.scrollToIndex(_selectedGameIndex);
  }

  /// Initiates the media preview sequence for the primary and secondary displays.
  void _startVideoTimer() {
    _videoTimer?.cancel();
    if (!mounted || _isGameLaunching) return;

    _videoTimer = Timer(_videoDelay, () async {
      if (!mounted) return;
      if (mounted && _selectedGame != null) {
        // Always attempt secondary display video update.
        await _updateSecondaryDisplayVideo(_selectedGame!);
        if (!mounted) return;

        // Primary display video is conditional based on user preference for 'Game Info'.
        final showGameInfo = context
            .read<SqliteConfigProvider>()
            .config
            .showGameInfo;
        if (showGameInfo) {
          await _initializeVideo(_selectedGame!);
        }
      }
    });
  }

  /// Initializes the video player for the primary UI, including volume and loop management.
  Future<void> _initializeVideo(GameModel game) async {
    if (!mounted ||
        _selectedGame == null ||
        _selectedGame != game ||
        _isVideoLoading) {
      return;
    }

    final showGameInfo = context
        .read<SqliteConfigProvider>()
        .config
        .showGameInfo;
    if (!showGameInfo) {
      return;
    }

    if (_isGameLaunching) {
      return;
    }

    setState(() => _isVideoLoading = true);

    final videoPath = _getVideoPath(game);
    final file = File(videoPath);
    final fileExists = _fileProvider.isInitialized
        ? await _fileProvider.fileExists(videoPath)
        : file.existsSync();

    if (!mounted || _selectedGame != game) {
      if (mounted) {
        setState(() {
          _isVideoLoading = false;
        });
      }
      return;
    }

    if (!fileExists) {
      if (mounted) {
        setState(() {
          _showVideo = false;
          _isVideoLoading = false;
        });
      }
      return;
    }

    try {
      if (!mounted || _selectedGame != game) {
        return;
      }

      // CRITICAL: Ensure previously active controllers are disposed to prevent resource leaks.
      if (_videoController != null) {
        try {
          _videoController!.pause();
          _videoController!.dispose();
        } catch (e) {
          _log.w('Error disposing old controller: $e');
        }
        _videoController = null;
      }

      final mainController = VideoPlayerController.file(
        file,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: false),
      );

      await mainController.initialize();

      if (mounted && _selectedGame == game && _selectedGame != null) {
        setState(() {
          _videoController = mainController;
          _showVideo = true;
          _isVideoLoading = false;
        });

        // Guard each await: navigation can dispose _videoController between calls.
        await mainController.setVolume(0.0);
        if (!mounted || _videoController != mainController) return;
        await mainController.setLooping(true);
        if (!mounted || _videoController != mainController) return;
        await mainController.play();
        if (!mounted || _videoController != mainController) return;

        _updateMusicDucking();
      } else {
        mainController.dispose();
        if (mounted) {
          setState(() {
            _isVideoLoading = false;
          });
        }
      }
    } catch (error) {
      _log.e('Error initializing video in LIST view: $error');
      if (mounted) {
        setState(() {
          _showVideo = false;
          _isVideoLoading = false;
        });
      }
    }
  }

  /// Resolves the absolute filesystem path for the targeted game video.
  String _getVideoPath(GameModel game) {
    final systemFolderName =
        (widget.system.folderName == 'all' ||
                widget.system.folderName == SystemFolderNames.favorites) &&
            game.systemFolderName != null
        ? game.systemFolderName!
        : widget.system.primaryFolderName;

    return game.getVideoPath(systemFolderName, _fileProvider);
  }

  @override
  Widget build(BuildContext context) {
    final isOled = context.select<ThemeProvider, bool>((t) => t.isOled);

    return PopScope(
      canPop: _canPop,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        _goBack();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(
          children: [
            // Ambient UI Layer: Shared fluid gradient for depth (non-OLED only).
            if (!isOled)
              Positioned.fill(
                child: Builder(
                  builder: (context) {
                    final bg = Theme.of(context).scaffoldBackgroundColor;
                    return Container(decoration: BoxDecoration(color: bg));
                  },
                ),
              ),

            // Content Layer: hide entirely while game dialog is active.
            if (!_isGameLaunching)
              SizedBox(
                child: _isLoading
                    ? _buildLoadingState()
                    : _games.isEmpty
                    ? _buildEmptyState()
                    : Consumer<SqliteConfigProvider>(
                        builder: (context, configProvider, child) {
                          if (widget.system.folderName == 'music') {
                            return _buildGamesList();
                          }
                          if (configProvider.config.gameViewMode == 'grid') {
                            return _buildGamesGrid();
                          } else if (configProvider.config.gameViewMode ==
                              'carousel') {
                            return _buildGamesCarousel();
                          }
                          return _buildGamesList();
                        },
                      ),
              ),

            // Navigation Layer: Visual alphabetical feedback for rapid scrolling.
            if (_currentLetter != null && !_isGameLaunching)
              _buildLetterIndicator(),
            GameViewModeDropdown(),
          ],
        ),
      ),
    );
  }

  /// Renders a large, semi-transparent alphabetical indicator for high-speed navigation.
  Widget _buildLetterIndicator() {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: _isNavigatingFast ? 1.0 : 0.0,
      child: RepaintBoundary(
        child: Center(
          child: Container(
            width: 120.r,
            height: 120.r,
            decoration: BoxDecoration(
              color: _letterIndicatorBg,
              borderRadius: BorderRadius.circular(24.r),
              border: Border.all(color: _letterIndicatorBorder, width: 2.r),
              boxShadow: [
                BoxShadow(
                  color: _letterIndicatorShadow,
                  blurRadius: 30.r,
                  spreadRadius: 5.r,
                ),
              ],
            ),
            child: Center(
              child: Text(
                _currentLetter!,
                style: TextStyle(
                  fontSize: 72.r,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  shadows: [
                    Shadow(color: _letterIndicatorTextShadow, blurRadius: 10.r),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Visual placeholder for initial data hydration.
  Widget _buildLoadingState() {
    return Center(
      child: Container(
        padding: EdgeInsets.all(32.w),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withValues(alpha: 0.25),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
            width: 1.r,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64.r,
              height: 64.r,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(32.r),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.3),
                    blurRadius: 16.r,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Theme.of(context).colorScheme.onSurface,
                  ),
                  strokeWidth: 3.r,
                ),
              ),
            ),
            SizedBox(height: 24.r),
            Text(
              AppLocale.loadingGames.getString(context),
              style: TextStyle(
                fontSize: 20.r,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 8.r),
            Text(
              AppLocale.preparingLibrary.getString(context),
              style: TextStyle(
                fontSize: 14.r,
                fontWeight: FontWeight.w400,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// specialized view for systems with zero detected media files.
  /// includes controls for recursive scanning and directory management.
  Widget _buildEmptyState() {
    bool currentScanValue = widget.system.recursiveScan;

    return Center(
      child: Container(
        constraints: BoxConstraints(maxWidth: 600.r),
        padding: EdgeInsets.symmetric(horizontal: 24.r, vertical: 16.r),
        margin: EdgeInsets.all(32.r),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.5),
              Theme.of(context).colorScheme.secondary.withValues(alpha: 0.45),
            ],
          ),
          borderRadius: BorderRadius.circular(16.r),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.shadow.withValues(alpha: 0.3),
              blurRadius: 16.r,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.shadow.withValues(alpha: 0.1),
              blurRadius: 32.r,
              offset: const Offset(0, 16),
            ),
          ],
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outline.withValues(alpha: 0.15),
            width: 1.r,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppLocale.noGamesFoundFor
                  .getString(context)
                  .replaceFirst(
                    '{name}',
                    widget.system.shortName ?? widget.system.realName,
                  ),
              style: TextStyle(
                fontSize: 16.r,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurface,
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4.r),
            Text(
              AppLocale.checkRomFiles.getString(context),
              style: TextStyle(
                fontSize: 11.r,
                fontWeight: FontWeight.w400,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.5),
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 16.r),

            // Configuration Component: Recursive Library Scanning.
            StatefulBuilder(
              builder: (context, setStateBuilder) {
                return Column(
                  children: [
                    Container(
                      margin: EdgeInsets.only(bottom: 12.r),
                      padding: EdgeInsets.symmetric(
                        horizontal: 12.r,
                        vertical: 8.r,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.05),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Symbols.folder_shared_rounded,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 16.r,
                          ),
                          SizedBox(width: 8.r),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppLocale.recursiveScan.getString(context),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12.r,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              Text(
                                AppLocale.recursiveScanSubtitle.getString(
                                  context,
                                ),
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.5),
                                  fontSize: 10.r,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(width: 16.r),
                          Switch(
                            value: currentScanValue,
                            activeThumbColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            onChanged: (value) async {
                              final oldSystem = widget.system;
                              setStateBuilder(() {
                                currentScanValue = value;
                              });

                              try {
                                await SystemRepository.setRecursiveScan(
                                  oldSystem.id!,
                                  value,
                                );

                                if (!context.mounted) return;
                                final configProvider = context
                                    .read<SqliteConfigProvider>();

                                await configProvider.scanSystems();
                                if (!context.mounted) return;

                                await Provider.of<SqliteDatabaseProvider>(
                                  context,
                                  listen: false,
                                ).loadDatabase();
                                if (!context.mounted) return;

                                await _loadGames();
                              } catch (e) {
                                _log.e('Error toggling recursive scan: $e');
                                if (!context.mounted) return;
                                AppNotification.showNotification(
                                  context,
                                  AppLocale.failedToSaveSetting.getString(
                                    context,
                                  ),
                                  type: NotificationType.error,
                                );
                              }
                            },
                          ),
                        ],
                      ),
                    ),

                    // Real-time Scan Progress Feedback.
                    Consumer<SqliteConfigProvider>(
                      builder: (context, provider, child) {
                        if (!provider.isScanning ||
                            provider.totalSystemsToScan <= 0) {
                          return const SizedBox.shrink();
                        }

                        return Container(
                          width: 320.r,
                          margin: EdgeInsets.only(bottom: 12.r),
                          padding: EdgeInsets.all(12.r),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.2),
                              width: 1.r,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    provider.scanStatus,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10.r,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                  ),
                                  Text(
                                    '${(provider.scanProgress * 100).toInt()}%',
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10.r,
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.primary,
                                        ),
                                  ),
                                ],
                              ),
                              SizedBox(height: 8.r),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4.r),
                                child: LinearProgressIndicator(
                                  value: provider.scanProgress,
                                  minHeight: 6.r,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.1),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                              ),
                              SizedBox(height: 4.r),
                              Text(
                                AppLocale.scanningSystemOf
                                    .getString(context)
                                    .replaceFirst(
                                      '{current}',
                                      provider.scannedSystemsCount.toString(),
                                    )
                                    .replaceFirst(
                                      '{total}',
                                      provider.totalSystemsToScan.toString(),
                                    ),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      fontSize: 9.r,
                                      color: Colors.white.withValues(
                                        alpha: 0.6,
                                      ),
                                    ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                );
              },
            ),

            // Navigation Component: Exit Action.
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  SfxService().playBackSound();
                  _goBack();
                },
                borderRadius: BorderRadius.circular(8.r),
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Container(
                    padding: EdgeInsets.only(
                      top: 4.r,
                      bottom: 4.r,
                      left: 8.r,
                      right: 12.r,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(8.r),
                      boxShadow: [
                        BoxShadow(
                          color: Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.3),
                          blurRadius: 8.r,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ColorFiltered(
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                          child: Image.asset(
                            'assets/images/gamepad/Xbox_B_button.png',
                            width: 18.r,
                            height: 18.r,
                          ),
                        ),
                        SizedBox(width: 6.r),
                        Text(
                          AppLocale.back.getString(context),
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14.r,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds the game carousel view with letter-based navigation.
  Widget _buildGamesCarousel() {
    return GamesCarousel(
      system: widget.system,
      games: _games,
      selectedIndex: _selectedGameIndex,
      fileProvider: _fileProvider,
      onGameSelected: (game) {
        setState(() {
          _selectedGame = game;
          _selectedGameIndex = _games.indexOf(game);
        });
        _performBackgroundOperationsForSelectedGame();
      },
      onBack: _goBack,
      onPlay: _selectCurrentGame,
      onFavorite: _toggleFavorite,
      onRandom: _showRandomGameDialog,
      onSettings: _handleStartButton,
      onScrape: _onScrapeCurrentGame,
      scrapingGameRomnames: _scrapingGameRomnames,
      scrapeProgress: _scrapeProgress,
    );
  }

  /// Builds the game grid view with box-2d images.
  Widget _buildGamesGrid() {
    return GamesGrid(
      system: widget.system,
      games: _games,
      selectedIndex: _selectedGameIndex,
      fileProvider: _fileProvider,
      onGameSelected: (game) {
        setState(() {
          _selectedGame = game;
          _selectedGameIndex = _games.indexOf(game);
        });
        _performBackgroundOperationsForSelectedGame();
      },
      onBack: _goBack,
      onPlay: _selectCurrentGame,
      onFavorite: _toggleFavorite,
      onRandom: _showRandomGameDialog,
      onSettings: _handleStartButton,
      onScrape: _onScrapeCurrentGame,
      scrapingGameRomnames: _scrapingGameRomnames,
      scrapeProgress: _scrapeProgress,
    );
  }

  /// Main layout orchestrator.
  /// Divides the viewport into a specialized browsing panel (left) and a detailed
  /// info/preview panel (right). The selected game's fanart is rendered behind
  /// the entire viewport so it peeks through both panels.
  Widget _buildGamesList() {
    final availableHeight =
        MediaQuery.of(context).size.height -
        MediaQuery.of(context).padding.top -
        MediaQuery.of(context).padding.bottom;
    final isMusic = widget.system.folderName == 'music';

    return Stack(
      children: [
        // Full-screen ambient fanart + overlay combined in a single layer
        // to avoid flickering caused by separate Positioned.fill compositing.
        if (!isMusic && _selectedGame != null)
          Positioned.fill(
            child: RepaintBoundary(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildGameFanartBackground(_selectedGame!),
                  Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.shadow.withValues(alpha: 0.2),
                  ),
                ],
              ),
            ),
          ),

        // Main content row: list panel + details panel.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sidebar: Interactive list of games or music tracks.
            Container(
              width: 180.r,
              height: availableHeight,
              margin: EdgeInsets.only(left: 58.r, top: 12.r, bottom: 12.r),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.90),
                borderRadius:
                    Theme.of(
                      context,
                    ).extension<CornerRadii>()?.radiusExternal ??
                    BorderRadius.circular(14.r),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                  width: 1.r,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.shadow.withValues(alpha: 0.5),
                    blurRadius: 3.r,
                    offset: Offset(2.r, 2.r),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius:
                    Theme.of(
                      context,
                    ).extension<CornerRadii>()?.radiusInternal ??
                    BorderRadius.circular(9.r),
                child: SizedBox(
                  width: 180.r,
                  height: availableHeight,
                  child: _buildGamesListPanel(),
                ),
              ),
            ),
            // Main Viewport: Rich metadata, video previews, and launch controls.
            Expanded(
              child: SizedBox(
                height: availableHeight,
                child: _buildGameDetailsPanel(),
              ),
            ),
          ],
        ),

        // Floating action buttons on the left side of the game list.
        if (!isMusic)
          Positioned(
            top: 12.r,
            left: 12.r,
            child: _buildGameListActionButtons(),
          ),
      ],
    );
  }

  /// Renders the selected game's fanart as a full-screen background.
  Widget _buildGameFanartBackground(GameModel game) {
    final imageSystemFolder =
        game.systemFolderName ?? widget.system.primaryFolderName;

    final fanartPath = game.getImagePath(
      imageSystemFolder,
      'fanarts',
      _fileProvider,
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 512),
      switchInCurve: Curves.easeOutExpo,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [...previousChildren, ?currentChild],
        );
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 1.0, end: 1.1).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOut),
            ),
            child: child,
          ),
        );
      },
      child: Builder(
        key: ValueKey('list_fanart_${game.romPath ?? game.romname}'),
        builder: (context) {
          final file = File(fanartPath);
          if (file.existsSync()) {
            return Image.file(
              file,
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              cacheWidth: 1920,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  /// Floating action buttons for the game list (back, view mode, random,
  /// favorite, scrape). Arranged vertically on the left side of the game list.
  Widget _buildGameListActionButtons() {
    final dropdownState = GameViewModeDropdown.globalKey.currentState;
    final viewModeKey = GlobalKey();
    final selectedGame = _selectedGame;

    final isFavorite = selectedGame?.isFavorite ?? false;
    final hasScreenScraper =
        widget.system.screenscraperId != null &&
        widget.system.screenscraperId != 0;
    final isScraping =
        selectedGame != null &&
        _scrapingGameRomnames.contains(selectedGame.romname);

    final description =
        _localizedDescription ??
        (selectedGame?.getDescriptionForLanguage('en').isEmpty == true
            ? AppLocale.noDescription.getString(context)
            : selectedGame?.getDescriptionForLanguage('en') ?? '');
    final isDescriptionMissing =
        description.isEmpty ||
        description == AppLocale.noDescription.getString(context) ||
        description.trim().isEmpty;

    return Container(
      padding: EdgeInsets.all(6.r),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIconButton(
            iconPath: 'assets/images/gamepad/Xbox_B_button.png',
            symbol: Symbols.arrow_back_rounded,
            color: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
            onTap: _goBack,
          ),
          SizedBox(height: 6.r),
          _buildIconButton(
            iconPath: 'assets/images/gamepad/Xbox_Y_button.png',
            symbol: isFavorite
                ? Symbols.favorite_rounded
                : Symbols.favorite_border_rounded,
            color: isFavorite
                ? Colors.redAccent
                : Theme.of(context).colorScheme.tertiary,
            foregroundColor: isFavorite
                ? Colors.white
                : Theme.of(context).colorScheme.onPrimary,
            onTap: selectedGame != null ? _toggleFavorite : () {},
          ),
          SizedBox(height: 6.r),
          if (hasScreenScraper && selectedGame != null) ...[
            _buildIconButton(
              iconPath: 'assets/images/gamepad/Xbox_View_button.png',
              symbol: isDescriptionMissing
                  ? Symbols.search_rounded
                  : Symbols.refresh_rounded,
              color: Theme.of(context).colorScheme.tertiary,
              foregroundColor: Theme.of(context).colorScheme.onPrimary,
              onTap: _onScrapeCurrentGame,
              isLoading: isScraping,
            ),
            SizedBox(height: 6.r),
          ],
          _buildIconButton(
            key: viewModeKey,
            iconPath: 'assets/images/gamepad/Xbox_X_button.png',
            symbol: Symbols.grid_view_rounded,
            color: Theme.of(context).colorScheme.tertiary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            onTap: () {
              SfxService().playNavSound();
              dropdownState?.showDropdownFrom(viewModeKey);
            },
          ),
          SizedBox(height: 6.r),
          _buildIconButton(
            iconPath: 'assets/images/gamepad/Left Stick Click.png',
            symbol: Symbols.casino_rounded,
            color: Theme.of(context).colorScheme.tertiary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            onTap: _showRandomGameDialog,
          ),
        ],
      ),
    );
  }

  /// Square action button (1:1 aspect ratio) with a gamepad hint icon and
  /// a Material Symbols icon stacked vertically. Optionally shows a loading
  /// indicator and disables taps while an async operation is in progress.
  Widget _buildIconButton({
    Key? key,
    required String iconPath,
    required IconData symbol,
    required Color color,
    Color? foregroundColor,
    required VoidCallback onTap,
    bool isLoading = false,
  }) {
    final fg = foregroundColor ?? Colors.white;
    const double buttonSize = 28.0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        onTap: isLoading ? null : onTap,
        borderRadius: BorderRadius.circular(6.r),
        child: Container(
          width: buttonSize.r,
          height: buttonSize.r,
          decoration: BoxDecoration(
            color: color.withValues(alpha: isLoading ? 0.5 : 0.85),
            borderRadius: BorderRadius.circular(6.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 2.r,
                offset: Offset(1.r, 1.r),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: isLoading
                ? [
                    SizedBox(
                      width: 14.r,
                      height: 14.r,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.r,
                        color: fg,
                      ),
                    ),
                  ]
                : [
                    Image.asset(
                      iconPath,
                      width: 11.r,
                      height: 11.r,
                      color: fg,
                      colorBlendMode: BlendMode.srcIn,
                    ),
                    SizedBox(height: 1.r),
                    Icon(symbol, size: 11.r, color: fg),
                  ],
          ),
        ),
      ),
    );
  }

  Widget _buildGamesListPanel() {
    return Column(
      children: [
        Expanded(
          child: widget.system.folderName == 'music'
              ? MusicList(
                  system: widget.system,
                  tracks: _games,
                  selectedIndex: _selectedGameIndex,
                  onTrackSelected: (track) {
                    setState(() {
                      _selectedGame = track;
                      _selectedGameIndex = _games.indexOf(track);
                    });
                    _performBackgroundOperationsForSelectedGame();
                  },
                  systemColor: widget.system.colorAsColor,
                  onBack: _goBack,
                  onRandom: _showRandomGameDialog,
                  isNavigatingFast: _isNavigatingFast,
                )
              : GameListView(
                  key: _gameListKey,
                  system: widget.system,
                  games: _games,
                  selectedIndex: _selectedGameIndex,
                  systemColor: widget.system.colorAsColor,
                  onGameSelected: _selectGame,
                  isAllMode:
                      widget.system.folderName == 'all' ||
                      widget.system.folderName == SystemFolderNames.favorites,
                  isNavigatingFast: _isNavigatingFast,
                  onGamepadReactivated: _reactivateGamepadNavigation,
                ),
        ),
      ],
    );
  }

  Widget _buildGameDetailsPanel() {
    if (_selectedGame == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64.r,
              height: 64.r,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.2),
                    Colors.white.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(32.r),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 1.r,
                ),
              ),
              child: Icon(
                Symbols.videogame_asset_rounded,
                size: 32.r,
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            SizedBox(height: 16.r),
            Text(
              AppLocale.selectAGame.getString(context),
              style: TextStyle(
                fontSize: 18.r,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.7),
                letterSpacing: 0.5,
              ),
            ),
            SizedBox(height: 8.r),
            Text(
              AppLocale.chooseGameFromList.getString(context),
              style: TextStyle(
                fontSize: 14.r,
                fontWeight: FontWeight.w400,
                color: Colors.white.withValues(alpha: 0.5),
                letterSpacing: 0.3,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (widget.system.folderName == 'music') {
      return Padding(
        padding: EdgeInsets.all(8.r),
        child: MusicPlayer(
          systemColor: widget.system.colorAsColor,
          onFavoriteToggled: () {
            // Re-sort the collection when favorite status is toggled via touch in MusicPlayer.
            _reorderGamesListKeepingVisualPosition();
          },
          onBack: _goBack,
        ),
      );
    }

    return Consumer<SyncManager>(
      builder: (context, syncManager, child) => GameDetailsCardList(
        game: _selectedGame!,
        system: widget.system,
        fileProvider: _fileProvider,
        showVideo: _showVideo,
        videoController: _videoController,
        isVideoLoading: _isVideoLoading,
        isAllMode:
            widget.system.folderName == 'all' ||
            widget.system.folderName == SystemFolderNames.favorites,
        retroAchievementsProvider: _retroAchievementsProvider,
        syncProvider: syncManager.active!,
        localizedDescription: _localizedDescription,
        isExternallyScraping: _scrapingGameRomnames.contains(
          _selectedGame!.romname,
        ),
        isNavigatingFast: _isNavigatingFast,
        isSecondaryScreenActive:
            _secondaryDisplayState?.value?.isSecondaryActive ?? false,
        onDeactivateNavigation: () => _gamepadNav.deactivate(),
        onReactivateNavigation: () => _gamepadNav.activate(),
        onRegisterOverlayState: (isOverlayOpen, isAchievementsOpen) {
          _isAchievementsOpen = isAchievementsOpen;
        },
        onRegisterNavigation:
            ({
              required moveUp,
              required moveDown,
              required moveLeft,
              required moveRight,
            }) {
              _moveAchievementUp = moveUp;
              _moveAchievementDown = moveDown;
              _moveAchievementLeft = moveLeft;
              _moveAchievementRight = moveRight;
            },
        onRegisterCloseOverlays: null,
        onRegisterTriggerAction: (triggerAction) {
          _triggerOverlayAction = triggerAction;
        },
        onRegisterSecondaryAction: (secondaryAction) {
          _secondaryOverlayAction = secondaryAction;
        },
        onRegisterTabNavigation: (tabNav) {
          _tabNavigationAction = tabNav;
        },
        onRegisterIsPlayingGameBlocked: (isBlocked) {
          _isPlayingGameBlocked = isBlocked;
        },
        onRegisterStartAction: (callback) {
          _startActionCallback = callback;
        },
        onPlayGame: _selectCurrentGame,
        onShowRandomGame: _showRandomGameDialog,
        onBack: _goBack,
        onGameUpdated: _handleGameUpdated, // Sync UI after metadata edits.
        onFavoriteToggled: _handleFavoriteToggledFromCard,
        onGameDeleted: _handleGameDeleted,
      ),
    );
  }

  /// Called when the card's touch favorite button is pressed.
  /// The DB toggle already happened in the card; mirror it into _games then resort.
  void _handleFavoriteToggledFromCard() {
    if (_selectedGame == null) return;
    setState(() {
      final gameIndex = _games.indexWhere(
        (g) => g.romname == _selectedGame!.romname,
      );
      if (gameIndex != -1) {
        final currentFavorite = _games[gameIndex].isFavorite ?? false;
        _games[gameIndex] = _games[gameIndex].copyWith(
          isFavorite: !currentFavorite,
        );
        _selectedGame = _games[gameIndex];
      }
    });
    _reorderGamesListKeepingVisualPosition();
  }

  /// Called after a game is permanently deleted. Removes it from the list and
  /// selects the previous game (or the next one if at the start).
  void _handleGameDeleted(String romname) {
    if (_games.isEmpty) return;

    _resetVideoState();

    final deletedIndex = _games.indexWhere((g) => g.romname == romname);
    if (deletedIndex == -1) return;

    final previousIndex = deletedIndex > 0 ? deletedIndex - 1 : 0;

    setState(() {
      _games.removeWhere((g) => g.romname == romname);
      _gameIndexMap = {for (int i = 0; i < _games.length; i++) _games[i]: i};

      if (_games.isEmpty) {
        _selectedGame = null;
        _selectedGameIndex = 0;
      } else {
        final newIndex = previousIndex.clamp(0, _games.length - 1);
        _selectedGame = _games[newIndex];
        _selectedGameIndex = newIndex;
      }
    });

    if (_games.isNotEmpty && _selectedGame != null) {
      // The list view's didUpdateWidget already recenters the new selection
      // when [_selectedGameIndex] changes, so an explicit scroll here is
      // redundant and can cause conflicting animations.
      _updateSecondaryDisplay(_selectedGame!);
      _updateBackground(_selectedGame!);
      _startVideoTimer();
    }
  }

  /// Synchronizes the selected game's metadata and refreshes the list sorting.
  Future<void> _handleGameUpdated() async {
    if (_selectedGame == null) return;

    try {
      _resetVideoState();

      // Fetch latest metadata from local storage.
      final updatedGame = await GameService.getGameDetails(
        widget.system,
        _selectedGame!.romname,
      );

      if (updatedGame != null) {
        setState(() {
          _selectedGame = updatedGame;

          final index = _games.indexWhere(
            (g) => g.romname == updatedGame.romname,
          );
          if (index != -1) {
            _games[index] = updatedGame;
          }
        });

        _loadLocalizedDescription();

        // Re-sort the collection following the edited game (name changes alter its rank).
        _reorderGamesListFollowingGame(updatedGame.romname);

        if (mounted && _selectedGame != null) {
          _updateSecondaryDisplay(updatedGame);
          _updateBackground(updatedGame);
          _startVideoTimer();
        }
      }
    } catch (e) {
      _log.e('Error updating game in list: $e');
    }
  }
}
