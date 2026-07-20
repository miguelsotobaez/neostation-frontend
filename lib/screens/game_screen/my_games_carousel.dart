import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/retro_achievements_game_info.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/providers/system_background_provider.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/services/retro_achievements_helper.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/screens/game_screen/game_details_card/dialogs/game_achievements_dialog.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/screens/app_screen.dart';
import 'package:neostation/widgets/native_carousel.dart';
import 'package:neostation/widgets/game_view_footer.dart';
import 'package:neostation/widgets/game_action_buttons.dart';
import 'package:neostation/constants/system_folder_names.dart';

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
  final Set<String> scrapingGameRomnames;
  final Map<String, double> scrapeProgress;

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
    this.scrapingGameRomnames = const {},
    this.scrapeProgress = const {},
  });

  @override
  State<GamesCarousel> createState() => _GamesCarouselState();

  /// Evicts memoized file-existence entries for [paths]. Call after replacing a
  /// game's image files on disk so the carousel re-checks the fresh artwork.
  static void evictArtworkCaches(Iterable<String> paths) {
    for (final path in paths) {
      _GamesCarouselState._fileExistsCache.remove(path);
    }
  }
}

class _GamesCarouselState extends State<GamesCarousel> {
  final GlobalKey<NativeCarouselState> _carouselKey = GlobalKey();
  final ScrollController _letterBarController = ScrollController();

  int _currentIndex = 0;
  late GamepadNavigation _gamepadNav;
  final Map<String, double> _letterWidthCache = {};
  static final Map<String, bool> _fileExistsCache = {};
  int _lastBgIndex = -1;

  /// Memoized `File.existsSync()` — synchronous disk stats on the UI thread
  /// while cards build are a known jank source. Entries are evicted by
  /// [GamesCarousel.evictArtworkCaches] when a scrape replaces artwork.
  static bool _fileExists(String path) =>
      _fileExistsCache.putIfAbsent(path, () => File(path).existsSync());

  GameInfoAndUserProgress? _currentGameInfo;
  bool _isLoadingAchievements = false;
  String? _achievementsTargetRomname;

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
    _initializeGamepad();
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
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _carouselKey.currentState?.jumpToPage(_currentIndex);
        _scrollToCurrentLetter();
        _updateBackground();
      });
    }
    if (widget.games != oldWidget.games) {
      _letterWidthCache.clear();
      if (_currentIndex >= widget.games.length) {
        _currentIndex = 0;
      }
    }
  }

  @override
  void dispose() {
    _cleanupGamepad();
    _letterBarController.dispose();
    super.dispose();
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
      onXButton: widget.onRandom,
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

  void _cleanupGamepad() {
    GamepadNavigationManager.popLayer('games_carousel');
    _gamepadNav.dispose();
  }

  void _onPageChanged(int index, CarouselPageChangeReason reason) {
    if (reason == CarouselPageChangeReason.manual) {
      SfxService().playNavSound();
    }
    setState(() {
      _currentIndex = index;
    });
    if (index < widget.games.length) {
      widget.onGameSelected(widget.games[index]);
    }
    _scrollToCurrentLetter();
    _updateBackground();
    _loadAchievementsForSelectedGame();
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

    // Clear the previous game's info immediately (not just after the async load
    // returns) so fast scrolling never shows the prior game's achievement
    // counts/icon while this load is pending.
    _achievementsTargetRomname = game.romname;
    if (mounted) {
      setState(() {
        _currentGameInfo = null;
        _isLoadingAchievements = true;
      });
    }

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

  String _resolveImagePath(GameModel game, String imageType) {
    final path = game.getImagePath(
      _folderForGame(game),
      imageType,
      widget.fileProvider,
    );
    if (_fileExists(path)) return path;
    return '';
  }

  Widget _buildFanartCard(GameModel game, bool isSelected) {
    final theme = Theme.of(context);
    final folder = _folderForGame(game);
    final screenshotPath = game.getScreenshotPath(folder, widget.fileProvider);
    final hasScreenshot = _fileExists(screenshotPath);
    final fanartPath = game.getImagePath(
      folder,
      'fanarts',
      widget.fileProvider,
    );
    final hasFanart = _fileExists(fanartPath);
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

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 60.r),
                child: NativeCarousel(
                  key: _carouselKey,
                  itemCount: widget.games.length,
                  initialIndex: _currentIndex.clamp(0, widget.games.length - 1),
                  itemBuilder: (context, index) {
                    final game = widget.games[index];
                    return KeyedSubtree(
                      key: ValueKey(game.romname),
                      child: isFanart
                          ? _buildFanartCard(game, index == _currentIndex)
                          : _buildBoxCard(game, index == _currentIndex),
                    );
                  },
                  onPageChanged: _onPageChanged,
                ),
              ),
            ),
            SizedBox(
              height: 36.r,
              child: SingleChildScrollView(
                controller: _letterBarController,
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: 4.r, vertical: 2.r),
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
            GameViewFooter(
              game: currentGame,
              onPlay: widget.onPlay,
              hasRetroAchievements: _hasRetroAchievementsFor(currentGame),
              isLoadingAchievements: _isLoadingAchievements,
              currentGameInfo: _currentGameInfo,
              onShowAchievements: _showAchievementsDialog,
            ),
            SizedBox(height: 8.r),
          ],
        ),
        Positioned(
          top: 12.r,
          left: 12.r,
          child: GameActionButtons(
            system: widget.system,
            selectedGame: currentGame,
            onBack: widget.onBack,
            onFavorite: widget.onFavorite ?? () {},
            onRandom: widget.onRandom ?? () {},
            onSettings: widget.onSettings ?? () {},
          ),
        ),
      ],
    );
  }
}
