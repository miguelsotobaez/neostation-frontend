import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/providers/system_background_provider.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/utils/letter_jump.dart';
import 'package:neostation/screens/app_screen.dart';
import 'package:neostation/widgets/game_view_mode_dropdown.dart';
import 'package:neostation/widgets/game_action_buttons.dart';
import 'package:neostation/widgets/legend_edge_reshow_zone.dart';
import 'package:neostation/services/game_legend_visibility.dart';
import 'package:neostation/sync/sync_manager.dart';
import 'package:neostation/widgets/native_carousel.dart';
import 'package:neostation/widgets/game_view_footer.dart';
import 'package:neostation/constants/system_folder_names.dart';
import 'package:neostation/models/retro_achievements_game_info.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/services/retro_achievements_helper.dart';
import 'package:neostation/screens/game_screen/game_details_card/dialogs/game_achievements_dialog.dart';

class GamesCarousel extends StatefulWidget {
  final SystemModel system;
  final List<GameModel> games;
  final int selectedIndex;
  final FileProvider fileProvider;
  final Function(GameModel) onGameSelected;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final VoidCallback? onFavorite;
  final VoidCallback? onRandom;
  final VoidCallback? onSettings;
  final VoidCallback? onScrape;
  final Set<String> scrapingGameRomnames;
  final Map<String, double> scrapeProgress;
  final int artworkVersion;

  /// Clears artwork dimension caches after files are added or overwritten.
  static void evictArtworkCaches(Iterable<String> paths) {
    if (paths.isEmpty) {
      _GamesCarouselState._imgSizeCache.clear();
      return;
    }
    for (final path in paths) {
      _GamesCarouselState._imgSizeCache.remove(path);
    }
  }

  const GamesCarousel({
    super.key,
    required this.system,
    required this.games,
    required this.selectedIndex,
    required this.fileProvider,
    required this.onGameSelected,
    required this.onBack,
    required this.onPlay,
    this.onFavorite,
    this.onRandom,
    this.onSettings,
    this.onScrape,
    this.scrapingGameRomnames = const {},
    this.scrapeProgress = const {},
    this.artworkVersion = 0,
  });

  @override
  State<GamesCarousel> createState() => _GamesCarouselState();
}

class _GamesCarouselState extends State<GamesCarousel> {
  final GlobalKey<NativeCarouselState> _carouselKey = GlobalKey();
  final ScrollController _letterBarController = ScrollController();

  int _currentIndex = 0;
  late GamepadNavigation _gamepadNav;

  // RetroAchievements info for the selected game (shown in the footer pill).
  GameInfoAndUserProgress? _currentGameInfo;
  bool _isLoadingAchievements = false;
  String? _achievementsTargetRomname;
  // Debounce so RA loads once selection settles rather than on every move.
  Timer? _achievementsDebounce;
  static const Duration _achievementsSettleDelay = Duration(milliseconds: 280);

  // Debounced "settled" selection driving the footer pill + action-button
  // legend, so that expensive chrome isn't rebuilt on every fast-swipe page
  // change. Memoized by signature (see _buildSettledChrome) so build() returns
  // identical instances during a burst and Flutter skips those subtrees.
  int _settledIndex = 0;
  Timer? _settleTimer;
  DateTime? _lastNavTime;
  bool _isNavigatingFast = false;
  static const Duration _fastNavThreshold = Duration(milliseconds: 150);
  static const Duration _chromeSettleDelay = Duration(milliseconds: 160);
  String? _chromeSig;
  Widget? _chromeFooter;
  Widget? _chromeLegend;
  final Map<String, double> _letterWidthCache = {};
  final Map<String, bool> _fileExistsCache = {};
  int _lastBgIndex = -1;

  static final Map<String, Size?> _imgSizeCache = {};

  static Size? _readImageSize(String path) {
    if (_imgSizeCache.containsKey(path)) return _imgSizeCache[path];
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final raf = file.openSync();
      try {
        final header = Uint8List(24);
        raf.readIntoSync(header);
        if (header[0] == 0x89 &&
            header[1] == 0x50 &&
            header[2] == 0x4E &&
            header[3] == 0x47) {
          final w = _readInt32BE(header, 16);
          final h = _readInt32BE(header, 20);
          if (w > 0 && h > 0 && w < 10000 && h < 10000) {
            final r = Size(w.toDouble(), h.toDouble());
            _imgSizeCache[path] = r;
            return r;
          }
        }
        if (header[0] == 0xFF && header[1] == 0xD8) {
          raf.setPositionSync(0);
          final len = raf.lengthSync().clamp(0, 65536).toInt();
          final buf = Uint8List(len);
          raf.readIntoSync(buf);
          int i = 2;
          while (i < buf.length - 9) {
            if (buf[i] != 0xFF) {
              i++;
              continue;
            }
            if (buf[i + 1] == 0xC0 || buf[i + 1] == 0xC2) {
              final h = (buf[i + 5] << 8) | buf[i + 6];
              final w = (buf[i + 7] << 8) | buf[i + 8];
              if (w > 0 && h > 0 && w < 10000 && h < 10000) {
                final r = Size(w.toDouble(), h.toDouble());
                _imgSizeCache[path] = r;
                return r;
              }
            }
            i += ((buf[i + 2] << 8) | buf[i + 3]) + 2;
          }
        }
      } finally {
        raf.closeSync();
      }
    } catch (_) {}
    return null;
  }

  static int _readInt32BE(List<int> bytes, int offset) =>
      (bytes[offset] << 24) |
      (bytes[offset + 1] << 16) |
      (bytes[offset + 2] << 8) |
      bytes[offset + 3];

  double? _boxAspectRatio(GameModel game) {
    if (game.box2dAspectRatio != null && game.box2dAspectRatio!.isNotEmpty) {
      final parts = game.box2dAspectRatio!.split('/');
      if (parts.length == 2) {
        final w = double.tryParse(parts[0]);
        final h = double.tryParse(parts[1]);
        if (w != null && h != null && w > 0 && h > 0) return w / h;
      }
    }
    final boxPath = _resolveImagePath(game, 'box2d');
    if (boxPath.isNotEmpty) {
      final size = _readImageSize(boxPath);
      if (size != null && size.width > 0 && size.height > 0) {
        return size.width / size.height;
      }
    }
    return null;
  }

  static const String _favoritesLabel = '★';

  bool get _hasFavoriteGames => widget.games.any((g) => g.isFavorite == true);

  List<String> get _uniqueLetters {
    final letters = <String>[];
    if (_hasFavoriteGames) {
      letters.add(_favoritesLabel);
    }
    for (final game in widget.games) {
      if (game.isFavorite == true) continue;

      final displayName = game.name.isNotEmpty ? game.name : game.realname;
      final letter = displayName.isNotEmpty
          ? displayName[0].toUpperCase()
          : '#';
      if (letters.isEmpty || letters.last != letter) {
        letters.add(letter);
      }
    }
    return letters;
  }

  String _getLetterForGame(GameModel game) {
    if (game.isFavorite == true) return _favoritesLabel;

    final displayName = game.name.isNotEmpty ? game.name : game.realname;
    return displayName.isNotEmpty ? displayName[0].toUpperCase() : '#';
  }

  int _getFirstGameIndexForLetter(String letter) {
    if (letter == _favoritesLabel) {
      for (int i = 0; i < widget.games.length; i++) {
        if (widget.games[i].isFavorite == true) return i;
      }
      return 0;
    }

    for (int i = 0; i < widget.games.length; i++) {
      if (widget.games[i].isFavorite == true) continue;
      if (_getLetterForGame(widget.games[i]) == letter) return i;
    }
    return 0;
  }

  int get _gamesLength => widget.games.isEmpty ? 1 : widget.games.length;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.selectedIndex.clamp(0, _gamesLength - 1);
    _settledIndex = _currentIndex;
    _initializeGamepad();
    GameLegendVisibility.hidden.addListener(_onLegendVisibilityChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToCurrentLetter();
      _updateBackground();
      _loadAchievementsForSelectedGame();
    });
  }

  @override
  void didUpdateWidget(GamesCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex &&
        widget.selectedIndex != _currentIndex) {
      setState(() {
        _currentIndex = widget.selectedIndex.clamp(0, _gamesLength - 1);
        _settledIndex = _currentIndex; // external jump: settle immediately
      });
      _settleTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _carouselKey.currentState?.jumpToPage(_currentIndex);
        _scrollToCurrentLetter();
        _updateBackground();
      });
      _scheduleAchievementsLoad();
    }
    if (widget.games != oldWidget.games) {
      _letterWidthCache.clear();
      if (_currentIndex >= widget.games.length) {
        _currentIndex = 0;
      }
    }
    if (widget.artworkVersion != oldWidget.artworkVersion) {
      _fileExistsCache.clear();
      _lastBgIndex = -1;
      // A scrape can add a preview video to the settled game, which changes
      // whether the footer's mute pill applies — the cache above no longer
      // answers it, so let the chrome rebuild against the new media too.
      _chromeSig = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _updateBackground());
    }
  }

  @override
  void dispose() {
    _achievementsDebounce?.cancel();
    _settleTimer?.cancel();
    GameLegendVisibility.hidden.removeListener(_onLegendVisibilityChanged);
    _cleanupGamepad();
    _letterBarController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Theme / MediaQuery / ScreenUtil may have changed; drop memoized chrome.
    _chromeSig = null;
  }

  void _initializeGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateLeft: () {
        SfxService().playNavSound();
        _carouselKey.currentState?.previousPage();
      },
      onNavigateRight: () {
        SfxService().playNavSound();
        _carouselKey.currentState?.nextPage();
      },
      onSelectItem: () {
        if (_currentIndex >= 0 && _currentIndex < widget.games.length) {
          widget.onPlay();
        }
      },
      onBack: widget.onBack,
      onFavorite: widget.onFavorite,
      onXButton: () {
        try {
          GameViewModeDropdown.globalKey.currentState?.showDropdown();
        } catch (_) {}
      },
      onLetterJump: _letterJump, // Held D-pad left/right → alphabet skipping.
      letterJumpAxis: LetterJumpAxis.horizontal,
      onLeftStickClick: widget.onRandom,
      onSelectButton: _toggleVideoMute, // Select tap - Mute preview video.
      onSelectModifierA: widget.onScrape, // Select + A - Scrape.
      onSelectModifierB: _toggleLegend, // Select + B - Hide/show legend.
      onSelectModifierY: widget.onRandom, // Select + Y - Random game.
      onSettings: widget.onSettings,
      onPreviousTab: AppNavigation.previousTab,
      onNextTab: AppNavigation.nextTab,
      onLeftBumper: AppNavigation.previousTab,
      onRightBumper: AppNavigation.nextTab,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'games_carousel',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });
  }

  /// Skips to the neighbouring alphabetical group once left/right has been
  /// held long enough (ES-DE style). Returns false at the ends of the alphabet
  /// so the caller falls back to a normal page step.
  bool _letterJump(bool forward) {
    if (widget.games.isEmpty) return false;

    final target = LetterJump.targetIndex(
      length: widget.games.length,
      currentIndex: _currentIndex,
      forward: forward,
      letterAt: (index) => _getLetterForGame(widget.games[index]),
    );
    if (target == null) return false;

    // Jump rather than animate: at letter-jump cadence an animated page slide
    // across dozens of entries would still be running when the next hop fires.
    _carouselKey.currentState?.jumpToPage(target);
    return true;
  }

  /// Select tap — toggles global video sound. The preview plays on the
  /// secondary display in this view; the config mutator propagates the new
  /// mute state to it, so there is nothing local to re-apply.
  void _toggleVideoMute() {
    if (!mounted) return;
    context.read<SqliteConfigProvider>().toggleVideoSound();
  }

  void _cleanupGamepad() {
    GamepadNavigationManager.popLayer('games_carousel');
    _gamepadNav.dispose();
  }

  void _onPageChanged(int index, CarouselPageChangeReason reason) {
    if (reason == CarouselPageChangeReason.manual) {
      SfxService().playNavSound();
    }
    final now = DateTime.now();
    _isNavigatingFast =
        _lastNavTime != null &&
        now.difference(_lastNavTime!) < _fastNavThreshold;
    _lastNavTime = now;
    setState(() {
      _currentIndex = index;
    });
    if (index < widget.games.length) {
      widget.onGameSelected(widget.games[index]);
    }
    _scheduleAchievementsLoad();
    _scheduleChromeSettle();
    _scrollToCurrentLetter();
    _updateBackground();
  }

  /// Advances the footer/legend's settled selection. A single (slow) page
  /// change updates it immediately; during a fast-swipe burst it is deferred
  /// until navigation settles, so the chrome isn't rebuilt every frame.
  void _scheduleChromeSettle() {
    _settleTimer?.cancel();
    if (!_isNavigatingFast) {
      if (_settledIndex != _currentIndex) {
        setState(() => _settledIndex = _currentIndex);
      }
      return;
    }
    _settleTimer = Timer(_chromeSettleDelay, () {
      if (mounted && _settledIndex != _currentIndex) {
        setState(() => _settledIndex = _currentIndex);
      }
    });
  }

  /// (Re)builds the footer pill + action-button legend only when the settled
  /// selection or its achievement/favorite state changes, so a fast-swipe
  /// burst reuses cached widget instances instead of rebuilding this chrome.
  void _buildSettledChrome() {
    final settledGame = widget.games[_settledIndex.clamp(0, _gamesLength - 1)];
    final hasRa = _hasRetroAchievementsFor(settledGame);
    final sig =
        '$_settledIndex|${settledGame.romname}|${settledGame.isFavorite}'
        '|$hasRa|$_isLoadingAchievements|${identityHashCode(_currentGameInfo)}';
    if (sig == _chromeSig && _chromeFooter != null && _chromeLegend != null) {
      return;
    }
    _chromeSig = sig;
    _chromeFooter = GameViewFooter(
      game: settledGame,
      onPlay: widget.onPlay,
      hasRetroAchievements: hasRa,
      isLoadingAchievements: _isLoadingAchievements,
      currentGameInfo: _currentGameInfo,
      onShowAchievements: _showAchievementsDialog,
      onToggleMute: _toggleVideoMute,
      hasVideo: _hasVideoFor(settledGame),
    );
    // Positioning/visibility is applied at the Stack level (AnimatedPositioned)
    // so Select + B can slide it without invalidating this memoized subtree.
    _chromeLegend = Consumer<SyncManager>(
      builder: (context, syncManager, child) => GameActionButtons(
        system: widget.system,
        selectedGame: settledGame,
        syncProvider: syncManager.active,
        onBack: widget.onBack,
        onFavorite: widget.onFavorite ?? () {},
        onViewMode: () =>
            GameViewModeDropdown.globalKey.currentState?.showDropdown(),
        onSettings: widget.onSettings ?? () {},
        onRandom: widget.onRandom,
        onScrape: widget.onScrape,
      ),
    );
  }

  /// Select + B — toggles the (session-global) vertical action-button legend.
  void _toggleLegend() {
    SfxService().playNavSound();
    GameLegendVisibility.toggle();
  }

  void _onLegendVisibilityChanged() {
    if (mounted) setState(() {});
  }

  bool get _isAllMode =>
      widget.system.folderName == SystemFolderNames.all ||
      widget.system.folderName == SystemFolderNames.favorites;

  SystemModel _effectiveSystemFor(GameModel game) {
    final systemFolderName = game.systemFolderName;
    if (systemFolderName == null || !_isAllMode) return widget.system;
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

  bool _hasRetroAchievementsFor(GameModel game) {
    final system = _effectiveSystemFor(game);
    return system.raId != null && system.raId != '0' && system.raId!.isNotEmpty;
  }

  /// Debounced entry point — coalesces rapid moves into a single load once the
  /// user stops on a game.
  void _scheduleAchievementsLoad() {
    final selectedRomname = widget.games.isEmpty
        ? null
        : widget.games[_currentIndex.clamp(0, widget.games.length - 1)].romname;
    if (selectedRomname != _achievementsTargetRomname) {
      _achievementsTargetRomname = selectedRomname;
      _currentGameInfo = null;
      _isLoadingAchievements = true;
    }
    _achievementsDebounce?.cancel();
    _achievementsDebounce = Timer(_achievementsSettleDelay, () {
      if (mounted) _loadAchievementsForSelectedGame();
    });
  }

  Future<void> _loadAchievementsForSelectedGame() async {
    if (widget.games.isEmpty) return;
    final game = widget.games[_currentIndex.clamp(0, widget.games.length - 1)];

    if (!_hasRetroAchievementsFor(game)) {
      if (mounted) {
        setState(() {
          _currentGameInfo = null;
          _isLoadingAchievements = false;
        });
      }
      return;
    }

    if (mounted) setState(() => _isLoadingAchievements = true);
    _achievementsTargetRomname = game.romname;

    try {
      final provider = context.read<RetroAchievementsProvider>();
      final info = await RetroAchievementsHelper.loadGameInfo(
        game: game,
        provider: provider,
        effectiveSystem: _effectiveSystemFor(game),
        isAllMode: _isAllMode,
      );
      if (mounted && _achievementsTargetRomname == game.romname) {
        setState(() {
          _currentGameInfo = info;
          _isLoadingAchievements = false;
        });
      }
    } catch (e) {
      if (mounted && _achievementsTargetRomname == game.romname) {
        setState(() {
          _currentGameInfo = null;
          _isLoadingAchievements = false;
        });
      }
    }
  }

  void _showAchievementsDialog() {
    if (widget.games.isEmpty) return;
    final game = widget.games[_currentIndex.clamp(0, widget.games.length - 1)];
    if (!_hasRetroAchievementsFor(game)) return;

    SfxService().playNavSound();
    showDialog(
      context: context,
      builder: (_) => GameAchievementsDialog(
        game: game,
        system: _effectiveSystemFor(game),
        retroAchievementsProvider: context.read<RetroAchievementsProvider>(),
      ),
    );
  }

  void _updateBackground() {
    if (!mounted || widget.games.isEmpty) return;
    if (_currentIndex < 0 || _currentIndex >= widget.games.length) return;
    if (_lastBgIndex == _currentIndex) return;
    _lastBgIndex = _currentIndex;

    final game = widget.games[_currentIndex];
    final folder = _folderForGame(game);

    String imagePath = game.getImagePath(
      folder,
      'fanarts',
      widget.fileProvider,
    );
    bool exists = _fileExistsCache.putIfAbsent(
      imagePath,
      () => File(imagePath).existsSync(),
    );

    if (!exists) {
      imagePath = game.getScreenshotPath(folder, widget.fileProvider);
      exists = _fileExistsCache.putIfAbsent(
        imagePath,
        () => File(imagePath).existsSync(),
      );
    }

    final ImageProvider imageProvider;
    if (exists) {
      imageProvider = FileImage(File(imagePath));
    } else {
      final sysId = widget.system.id;
      final path = 'assets/images/logos/$sysId.webp';
      imageProvider = AssetImage(path);
      imagePath = path;
    }

    context.read<SystemBackgroundProvider>().updateImage(
      imageProvider,
      imagePath: imagePath,
    );
  }

  void _scrollToCurrentLetter() {
    if (!_letterBarController.hasClients || widget.games.isEmpty) return;

    final currentLetter = _getLetterForGame(widget.games[_currentIndex]);
    final letters = _uniqueLetters;
    final letterIndex = letters.indexOf(currentLetter);
    if (letterIndex < 0) return;

    final textStyle = TextStyle(fontSize: 11.r, fontWeight: FontWeight.bold);
    final selectedTextStyle = textStyle.copyWith(fontWeight: FontWeight.w800);
    double offset = 0;
    for (int i = 0; i < letterIndex; i++) {
      offset += _calculateLetterWidth(letters[i], selectedTextStyle) + 6.r;
    }
    final letterWidth = _calculateLetterWidth(currentLetter, selectedTextStyle);
    final screenWidth = MediaQuery.of(context).size.width;
    double targetOffset = offset - (screenWidth / 2) + (letterWidth / 2);
    targetOffset = targetOffset.clamp(
      0.0,
      _letterBarController.position.maxScrollExtent,
    );

    _letterBarController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }

  double _calculateLetterWidth(String letter, TextStyle style) {
    final cacheKey = '$letter|${style.fontSize}|${style.fontWeight?.value}';
    return _letterWidthCache.putIfAbsent(cacheKey, () {
      final textPainter = TextPainter(
        text: TextSpan(text: letter, style: style),
        textAlign: TextAlign.center,
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout();
      return textPainter.width + 20.r;
    });
  }

  double _getLetterBarOffset(
    String targetLetter,
    List<String> letters,
    TextStyle style,
  ) {
    double offset = 0;
    for (final letter in letters) {
      if (letter == targetLetter) break;
      offset += _calculateLetterWidth(letter, style) + 6.r;
    }
    return offset;
  }

  String _folderForGame(GameModel game) {
    if ((widget.system.folderName == SystemFolderNames.all ||
            widget.system.folderName == SystemFolderNames.favorites) &&
        game.systemFolderName != null) {
      return game.systemFolderName!;
    }
    return widget.system.primaryFolderName;
  }

  /// Whether the game has a preview video, so the footer knows whether a mute
  /// control is worth showing.
  ///
  /// Scraped media lives on the plain filesystem (unlike SAF ROM paths), so a
  /// sync stat is safe, and this only runs when the selection settles — not
  /// per frame. Cached alongside the background lookups.
  bool _hasVideoFor(GameModel game) {
    final videoPath = game.getVideoPath(
      _folderForGame(game),
      widget.fileProvider,
    );
    return _fileExistsCache.putIfAbsent(
      videoPath,
      () => File(videoPath).existsSync(),
    );
  }

  String _resolveImagePath(GameModel game, String imageType) {
    final path = game.getImagePath(
      _folderForGame(game),
      imageType,
      widget.fileProvider,
    );
    if (File(path).existsSync()) return path;
    return '';
  }

  Widget _buildFanartCard(GameModel game, bool isSelected) {
    final theme = Theme.of(context);
    final folder = _folderForGame(game);
    final screenshotPath = game.getScreenshotPath(folder, widget.fileProvider);
    final hasScreenshot = File(screenshotPath).existsSync();
    final fanartPath = game.getImagePath(
      folder,
      'fanarts',
      widget.fileProvider,
    );
    final hasFanart = File(fanartPath).existsSync();
    final bgPath = hasFanart
        ? fanartPath
        : (hasScreenshot ? screenshotPath : '');

    return Container(
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.all(5.r),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 8.r,
            offset: Offset(2.r, 2.r),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24.r),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (bgPath.isNotEmpty)
              Image.file(
                File(bgPath),
                key: ValueKey(bgPath),
                fit: BoxFit.cover,
                cacheWidth: 1024,
                errorBuilder: (ctx, e, s) => _buildFallbackCard(game, theme),
              )
            else
              _buildFallbackCard(game, theme),
            if (bgPath.isNotEmpty)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.6),
                      Colors.black.withValues(alpha: 0.9),
                    ],
                    stops: const [0.0, 0.4, 0.7, 1.0],
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildWheelOverlay(game),
            ),
            if (game.isFavorite == true)
              Positioned(
                top: 8.r,
                right: 8.r,
                child: Container(
                  width: 32.r,
                  height: 32.r,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Symbols.favorite_rounded,
                    size: 18.r,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            if (widget.scrapingGameRomnames.contains(game.romname))
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildScrapeProgress(game),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrapeProgress(GameModel game) {
    final progress = widget.scrapeProgress[game.romname] ?? 0.0;
    return Container(
      height: 24.r,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24.r)),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12.r),
      child: Row(
        children: [
          Icon(Symbols.search_rounded, size: 14.r, color: Colors.white70),
          SizedBox(width: 6.r),
          Expanded(
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          SizedBox(width: 6.r),
          Text(
            '${(progress * 100).toInt()}%',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 11.r,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackCard(GameModel game, ThemeData theme) {
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.videogame_asset_rounded,
              size: 64.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            SizedBox(height: 12.r),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.r),
              child: Text(
                game.name.isNotEmpty ? game.name : game.realname,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 14.r,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWheelOverlay(GameModel game) {
    final wheelPath = _resolveImagePath(game, 'wheels');
    if (wheelPath.isNotEmpty) {
      return Container(
        padding: EdgeInsets.fromLTRB(48.r, 4.r, 48.r, 8.r),
        child: Image.file(
          File(wheelPath),
          key: ValueKey(wheelPath),
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
          cacheWidth: 512,
          errorBuilder: (ctx, e, s) => const SizedBox.shrink(),
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildBoxCard(GameModel game, bool isSelected) {
    final theme = Theme.of(context);
    final boxPath = _resolveImagePath(game, 'box2d');
    final hasBox = boxPath.isNotEmpty;
    final ratio = _boxAspectRatio(game) ?? 1.0;

    if (!hasBox) {
      return Center(
        child: Stack(
          children: [
            _buildBoxFallback(game, theme),
            if (game.isFavorite == true)
              Positioned(
                top: 8.r,
                right: 8.r,
                child: Container(
                  width: 32.r,
                  height: 32.r,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Symbols.favorite_rounded,
                    size: 18.r,
                    color: Colors.redAccent,
                  ),
                ),
              ),
            if (widget.scrapingGameRomnames.contains(game.romname))
              _buildScrapeProgress(game),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth;
        final maxH = constraints.maxHeight;

        double cardW, cardH;
        if (maxW / ratio <= maxH) {
          cardW = maxW;
          cardH = maxW / ratio;
        } else {
          cardH = maxH;
          cardW = maxH * ratio;
        }

        return Center(
          child: Container(
            width: cardW,
            height: cardH,
            clipBehavior: Clip.antiAlias,
            margin: EdgeInsets.all(5.r),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8.r),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isSelected ? 0.6 : 0.3),
                  blurRadius: isSelected ? 12.r : 6.r,
                  offset: Offset(2.r, 2.r),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.r),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(
                    File(boxPath),
                    key: ValueKey(boxPath),
                    fit: BoxFit.cover,
                    cacheWidth: 1024,
                    errorBuilder: (ctx, e, s) => _buildBoxFallback(game, theme),
                  ),
                  if (game.isFavorite == true)
                    Positioned(
                      top: 8.r,
                      right: 8.r,
                      child: Container(
                        width: 32.r,
                        height: 32.r,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Symbols.favorite_rounded,
                          size: 18.r,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                  if (widget.scrapingGameRomnames.contains(game.romname))
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: _buildScrapeProgress(game),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBoxFallback(GameModel game, ThemeData theme) {
    return _buildFallbackCard(game, theme);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.games.isEmpty) {
      return Center(
        child: Text(
          'No games',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
      );
    }

    final config = context.watch<SqliteConfigProvider>().config;
    final isFanart = config.gameCarouselCardStyle != 'box';
    final theme = Theme.of(context);
    final currentGame =
        widget.games[_currentIndex.clamp(0, widget.games.length - 1)];
    final letters = _uniqueLetters;
    final currentLetter = _getLetterForGame(currentGame);

    final textStyle = TextStyle(
      color: theme.colorScheme.onSurface,
      fontSize: 11.r,
      fontWeight: FontWeight.normal,
    );
    final selectedTextStyle = textStyle.copyWith(
      color: theme.colorScheme.onPrimary,
      fontWeight: FontWeight.w800,
    );

    _buildSettledChrome();

    return Stack(
      children: [
        Column(
          children: [
            // #188 layout: drop the top spacer so the carousel gets the full
            // height (bigger cards sit closer together). Pad symmetrically so
            // the centered card stays centered on-screen while still clearing
            // the vertical legend on the left.
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 60.r),
                child: NativeCarousel(
                  key: _carouselKey,
                  itemCount: widget.games.length,
                  initialIndex: _currentIndex.clamp(0, widget.games.length - 1),
                  itemBuilder: (context, index) {
                    final game = widget.games[index];
                    final isCentred = index == _currentIndex;
                    return KeyedSubtree(
                      key: ValueKey(game.romname),
                      child: GestureDetector(
                        // Tapping an off-centre card brings it to the middle;
                        // tapping the centred one plays it, so touch users
                        // never need the footer's A button.
                        onTap: () {
                          if (isCentred) {
                            SfxService().playEnterSound();
                            widget.onPlay();
                          } else {
                            SfxService().playNavSound();
                            _carouselKey.currentState?.animateToPage(index);
                          }
                        },
                        child: isFanart
                            ? _buildFanartCard(game, isCentred)
                            : _buildBoxCard(game, isCentred),
                      ),
                    );
                  },
                  onPageChanged: _onPageChanged,
                ),
              ),
            ),
            // Tight letter-bar box (chip height, no vertical slack) sits low
            // against the footer. Reclaiming the old slack in real layout (vs a
            // visual translate) lets the carousel above grow into it, so the
            // artwork gets slightly bigger with no gap beneath it.
            SizedBox(
              height: 30.r,
              child: SingleChildScrollView(
                controller: _letterBarController,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 4.r),
                child: Stack(
                  children: [
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 120),
                      curve: Curves.easeInOut,
                      left: _getLetterBarOffset(
                        currentLetter,
                        letters,
                        selectedTextStyle,
                      ),
                      top: 0,
                      bottom: 0,
                      width: _calculateLetterWidth(
                        currentLetter,
                        selectedTextStyle,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondary,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                    ),
                    Row(
                      children: letters.map((letter) {
                        final isSelected = letter == currentLetter;
                        final w = _calculateLetterWidth(
                          letter,
                          selectedTextStyle,
                        );
                        return GestureDetector(
                          onTap: () {
                            SfxService().playNavSound();
                            final gi = _getFirstGameIndexForLetter(letter);
                            _carouselKey.currentState?.animateToPage(gi);
                          },
                          child: Container(
                            width: w,
                            height: 30.r,
                            margin: EdgeInsets.only(right: 6.r),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.1,
                              ),
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Text(
                              letter,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: isSelected ? selectedTextStyle : textStyle,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ),
            // Footer pill driven by the debounced settled selection and
            // memoized (see _buildSettledChrome) so it is not rebuilt on every
            // fast-swipe frame.
            // Flush to the bottom (no trailing spacer) so the footer sits at
            // the same vertical position as the grid view's footer.
            _chromeFooter!,
          ],
        ),
        // Vertical action-button legend (shared with the game list view);
        // also memoized on the settled selection. Select + B slides it off the
        // left edge. The centered carousel itself is left in place (there is no
        // left-gutter to reflow into for a centered PageView).
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          top: 12.r,
          bottom: 12.r,
          left: GameLegendVisibility.hidden.value ? -72.r : 10.r,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: GameLegendVisibility.hidden.value ? 0.0 : 1.0,
            child: Align(
              alignment: Alignment.topLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: _chromeLegend!,
              ),
            ),
          ),
        ),
        // Touch: swipe-right from the left edge reveals a hidden legend.
        const LegendEdgeReshowZone(),
      ],
    );
  }
}
