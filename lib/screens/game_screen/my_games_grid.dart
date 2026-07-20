import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/retro_achievements_game_info.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/services/retro_achievements_helper.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/utils/game_utils.dart';
import 'package:neostation/screens/game_screen/game_details_card/dialogs/game_achievements_dialog.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/repositories/game_repository.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/widgets/game_view_footer.dart';
import 'package:neostation/widgets/game_action_buttons.dart';
import 'package:neostation/constants/system_folder_names.dart';
import 'package:neostation/widgets/selection_grid/grid_navigation.dart';
import 'package:neostation/widgets/selection_grid/selection_grid.dart';
import 'package:neostation/widgets/selection_grid/selection_grid_geometry.dart';

import '../../themes/corner_radii.dart';

class GamesGrid extends StatefulWidget {
  final SystemModel system;
  final List<GameModel> games;
  final int selectedIndex;
  final FileProvider fileProvider;
  final Function(GameModel) onGameSelected;
  final VoidCallback onBack;
  final VoidCallback onPlay;
  final VoidCallback onFavorite;
  final VoidCallback onRandom;
  final VoidCallback? onSettings;
  final Set<String> scrapingGameRomnames;
  final Map<String, double> scrapeProgress;

  const GamesGrid({
    super.key,
    required this.system,
    required this.games,
    required this.selectedIndex,
    required this.fileProvider,
    required this.onGameSelected,
    required this.onBack,
    required this.onPlay,
    required this.onFavorite,
    required this.onRandom,
    this.onSettings,
    this.scrapingGameRomnames = const {},
    this.scrapeProgress = const {},
  });

  @override
  State<GamesGrid> createState() => _GamesGridState();

  /// Evicts memoized artwork entries (file-existence and image dimensions)
  /// for [paths]. Call after replacing a game's image files on disk, e.g.
  /// from the game settings dialog's artwork editor or a scrape.
  static void evictArtworkCaches(Iterable<String> paths) {
    _GamesGridState._evictArtworkCaches(paths);
  }
}

class _GamesGridState extends State<GamesGrid> {
  late GamepadNavigation _gamepadNav;
  int _selectedIndex = 0;
  int _crossAxisCount = 5;

  // Bumped whenever card *content* (as opposed to selection) changes, so the
  // SelectionGrid rebuilds its cached card widgets. A pure selection move
  // deliberately leaves this untouched — the cards are then reused and only
  // the highlight repositions.
  int _gridRevision = 0;
  bool _isNavigatingFast = false;

  GameInfoAndUserProgress? _currentGameInfo;
  bool _isLoadingAchievements = false;
  String? _achievementsTargetRomname;

  // RetroAchievements info is loaded per selected game, but firing it (plus its
  // setState churn) on every gamepad move floods the UI thread during fast
  // navigation. Debounce so it loads once the selection settles.
  Timer? _achievementsDebounce;
  static const Duration _achievementsSettleDelay = Duration(milliseconds: 280);

  /// Debounced entry point for the navigation hot path — coalesces rapid moves
  /// into a single load once the user stops on a game.
  void _scheduleAchievementsLoad() {
    // Reflect the new selection in the footer's RA indicator immediately, so
    // fast navigation never shows the *previous* game's achievement counts/icon
    // while the (debounced) load is pending. Fields are mutated directly — every
    // caller already has a rebuild in flight (setState on the move, or a
    // didUpdateWidget). The actual load below fills in the real data on settle.
    final selectedRomname = widget.games.isEmpty
        ? null
        : widget
              .games[_selectedIndex.clamp(0, widget.games.length - 1)]
              .romname;
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

  DateTime? _lastNavTime;
  static const Duration _fastNavThreshold = Duration(milliseconds: 150);

  // Layout geometry — single source of truth shared by the cards and the
  // selection highlight (see SelectionGrid). Cached and recomputed only when
  // width / columns / game count / card style / artwork dimensions change.
  SelectionGridGeometry? _geometry;
  double? _geoWidth;
  int? _geoCols;
  int? _geoGameCount;
  bool? _geoIsFanart;

  // Image dimension cache
  static final Map<String, Size?> _imageSizeCache = {};

  // File existence cache — calling existsSync on the UI thread while cards
  // rebuild during scroll is a known jank source in image grids, so results
  // are memoized. Entries are evicted when a scrape replaces artwork on disk
  // (see didUpdateWidget).
  static final Map<String, bool> _fileExistsCache = {};

  static bool _fileExists(String path) {
    final cached = _fileExistsCache[path];
    if (cached != null) return cached;
    final exists = File(path).existsSync();
    _fileExistsCache[path] = exists;
    return exists;
  }

  /// Backing implementation for [GamesGrid.evictArtworkCaches].
  static void _evictArtworkCaches(Iterable<String> paths) {
    for (final path in paths) {
      _fileExistsCache.remove(path);
      _imageSizeCache.remove(path);
    }
  }

  // Visible index tracking for lazy dimension loading
  final Set<int> _loadedDims = {};
  bool _needsDimReload = false;
  bool _dimReloadScheduled = false;

  // Pinch gesture tracking
  final Map<int, Offset> _activePointers = {};
  double? _lastPinchDistance;
  DateTime? _lastPinchTime;

  // Card size label
  final ValueNotifier<String?> _cardSizeLabel = ValueNotifier(null);
  Timer? _cardSizeLabelTimer;

  // ---- Image size reading ----
  static Size? _readImageSize(String path) {
    if (_imageSizeCache.containsKey(path)) return _imageSizeCache[path];
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
            _imageSizeCache[path] = r;
            return r;
          }
        }
        if (header[0] == 0xFF && header[1] == 0xD8) {
          raf.setPositionSync(0);
          final len = (raf.lengthSync()).clamp(0, 65536).toInt();
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
                _imageSizeCache[path] = r;
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

  String _folderForGame(GameModel game) {
    if ((widget.system.folderName == SystemFolderNames.all ||
            widget.system.folderName == SystemFolderNames.favorites) &&
        game.systemFolderName != null) {
      return game.systemFolderName!;
    }
    return widget.system.primaryFolderName;
  }

  String _box2dPath(int index) {
    final game = widget.games[index];
    return game.getImagePath(
      _folderForGame(game),
      'box2d',
      widget.fileProvider,
    );
  }

  String _fanartPath(int index) {
    final game = widget.games[index];
    return game.getImagePath(
      _folderForGame(game),
      'fanarts',
      widget.fileProvider,
    );
  }

  String _screenshotPath(int index) {
    final game = widget.games[index];
    return game.getScreenshotPath(_folderForGame(game), widget.fileProvider);
  }

  bool get _isFanart =>
      context.read<SqliteConfigProvider>().config.gameCarouselCardStyle ==
      'fanart';

  double _box2dAspectRatio(int index) {
    final game = widget.games[index];
    // 1. From DB
    if (game.box2dAspectRatio != null && game.box2dAspectRatio!.isNotEmpty) {
      final parts = game.box2dAspectRatio!.split('/');
      if (parts.length == 2) {
        final w = double.tryParse(parts[0]);
        final h = double.tryParse(parts[1]);
        if (w != null && h != null && w > 0 && h > 0) return w / h;
      }
    }
    // 2. From file header
    final path = _box2dPath(index);
    final size = _readImageSize(path);
    if (size != null && size.width > 0 && size.height > 0) {
      // Save to DB for next time
      final ratio = '${size.width.toInt()}/${size.height.toInt()}';
      _scheduleAspectRatioSave(game, ratio);
      return size.width / size.height;
    }
    return 1.0; // 1:1 fallback
  }

  // ---- Card height strategies (one per card style) ----

  /// Fanart cards show only the artwork, with just enough room for padding.
  double _fanartCardHeight(int index, double cardWidth) => cardWidth;

  /// Box2d cards derive their height from the artwork's aspect ratio.
  ///
  /// Content width = card width minus inner padding (4.r each side).
  /// Outer padding is already accounted for by the row/cell layout.
  double _box2dCardHeight(int index, double cardWidth) =>
      (cardWidth - 8.r) / _box2dAspectRatio(index) + 12.r;

  final Set<String> _pendingSaves = {};
  void _scheduleAspectRatioSave(GameModel game, String ratio) {
    final key = '${game.systemId}_${game.romname}';
    if (_pendingSaves.contains(key)) return;
    _pendingSaves.add(key);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _pendingSaves.remove(key);
      if (game.systemId != null) {
        GameRepository.updateBox2dAspectRatio(
          game.systemId!,
          game.romname,
          ratio,
        );
      }
    });
  }

  // ---- Layout geometry (cached; recomputed only on invalidating changes) ----
  SelectionGridGeometry _geometryFor(double contentWidth) {
    final isFanart = _isFanart;
    final cached = _geometry;
    if (cached != null &&
        _geoWidth == contentWidth &&
        _geoCols == _cols &&
        _geoGameCount == widget.games.length &&
        _geoIsFanart == isFanart &&
        !_needsDimReload) {
      return cached;
    }
    _geoWidth = contentWidth;
    _geoCols = _cols;
    _geoGameCount = widget.games.length;
    _geoIsFanart = isFanart;
    _needsDimReload = false;
    _loadedDims.clear();
    return _geometry = computeSelectionGridGeometry(
      itemCount: widget.games.length,
      columns: _cols,
      availableWidth: contentWidth,
      spacingX: 6.0.r,
      spacingY: 6.0.r,
      itemHeightFor: isFanart ? _fanartCardHeight : _box2dCardHeight,
    );
  }

  // Lazy dimension loading for newly visible cards (box2d style only)
  void _ensureDims(int index) {
    if (_isFanart) return;
    if (_loadedDims.contains(index)) return;
    final path = _box2dPath(index);
    final hadBefore = _imageSizeCache.containsKey(path);
    final size = _readImageSize(path); // touches cache, fills in dimension
    _loadedDims.add(index);
    if (!hadBefore && size != null && !_dimReloadScheduled) {
      _needsDimReload = true;
      _dimReloadScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _dimReloadScheduled = false;
        if (mounted && _needsDimReload) {
          setState(() {});
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.selectedIndex.clamp(
      0,
      (widget.games.length - 1).clamp(0, 999999),
    );
    _updateCrossAxisCount();
    _initializeGamepad();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _gamepadNav.initialize();
        GamepadNavigationManager.pushLayer(
          'games_grid',
          onActivate: () => _gamepadNav.activate(),
          onDeactivate: () => _gamepadNav.deactivate(),
        );
        _loadAchievementsForSelectedGame();
      }
    });
  }

  void _updateCrossAxisCount() {
    try {
      final config = context.read<SqliteConfigProvider>().config;
      switch (config.gameGridColumns) {
        case 'S':
          _crossAxisCount = 7;
          break;
        case 'M':
          _crossAxisCount = 6;
          break;
        case 'L':
          _crossAxisCount = 5;
          break;
        case 'XL':
          _crossAxisCount = 4;
          break;
        default:
          _crossAxisCount = 6;
      }
    } catch (_) {
      _crossAxisCount = 5;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateCrossAxisCount();
  }

  void _adjustGameGridDensity(int delta) {
    try {
      final provider = context.read<SqliteConfigProvider>();
      final sizes = ['S', 'M', 'L', 'XL'];
      final currentIndex = sizes.indexOf(provider.config.gameGridColumns);
      if (currentIndex == -1) return;
      final newIndex = (currentIndex + delta).clamp(0, sizes.length - 1);
      if (newIndex != currentIndex) {
        final newSize = sizes[newIndex];
        provider.updateGameGridColumns(newSize);
        _updateCrossAxisCount();
        _showCardSizeLabel(newSize);
        // The geometry cache detects the column change on the next build and
        // SelectionGrid re-centers the selection automatically.
        setState(() {});
      }
    } catch (_) {}
  }

  void _showCardSizeLabel(String size) {
    _cardSizeLabelTimer?.cancel();
    _cardSizeLabel.value = size;
    _cardSizeLabelTimer = Timer(const Duration(milliseconds: 1200), () {
      _cardSizeLabel.value = null;
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.position;
  }

  void _handlePointerMove(PointerMoveEvent event) {
    _activePointers[event.pointer] = event.position;
    if (_activePointers.length < 2) return;
    final now = DateTime.now();
    if (_lastPinchTime != null &&
        now.difference(_lastPinchTime!).inMilliseconds < 120) {
      return;
    }
    final positions = _activePointers.values.toList();
    final distance = (positions[0] - positions[1]).distance;
    if (_lastPinchDistance != null) {
      final deltaDistance = distance - _lastPinchDistance!;
      if (deltaDistance > 35) {
        _adjustGameGridDensity(1);
        _lastPinchDistance = distance;
        _lastPinchTime = now;
      } else if (deltaDistance < -35) {
        _adjustGameGridDensity(-1);
        _lastPinchDistance = distance;
        _lastPinchTime = now;
      }
    } else {
      _lastPinchDistance = distance;
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) _lastPinchDistance = null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) _lastPinchDistance = null;
  }

  @override
  void didUpdateWidget(GamesGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateCrossAxisCount();
    // Card *content* changed (not just selection) — bump the revision so the
    // SelectionGrid rebuilds cached card widgets instead of reusing stale ones.
    //   - games: gets a fresh list instance on favorite toggle / reorder /
    //     update, and length changes on delete (which also re-keys geometry),
    //     so an identity check catches those.
    //   - scrape sets/maps are `final` and mutated in place (stable identity),
    //     so bump while a scrape is active — or was on the previous frame — to
    //     keep progress bars animating and to clear them when the scrape ends.
    if (!identical(widget.games, oldWidget.games) ||
        widget.scrapingGameRomnames.isNotEmpty ||
        oldWidget.scrapingGameRomnames.isNotEmpty) {
      _gridRevision++;
    }
    // Artwork replaced by a finished scrape must be re-checked on disk.
    final finishedScrapes = oldWidget.scrapingGameRomnames.difference(
      widget.scrapingGameRomnames,
    );
    if (finishedScrapes.isNotEmpty) {
      _evictArtworkCachesFor(finishedScrapes);
    }
    // Skip the resync when the parent is only echoing back a selection this
    // grid already reported — otherwise achievements load twice per move.
    if (widget.selectedIndex != oldWidget.selectedIndex &&
        widget.selectedIndex != _selectedIndex) {
      _selectedIndex = widget.selectedIndex.clamp(
        0,
        (widget.games.length - 1).clamp(0, 999999),
      );
      _scheduleAchievementsLoad();
    }
  }

  /// Drops memoized existence/dimension entries for games whose artwork may
  /// have changed on disk (e.g. after a scrape completed).
  void _evictArtworkCachesFor(Set<String> romnames) {
    for (final game in widget.games) {
      if (!romnames.contains(game.romname)) continue;
      final folder = _folderForGame(game);
      final paths = [
        game.getImagePath(folder, 'fanarts', widget.fileProvider),
        game.getImagePath(folder, 'wheels', widget.fileProvider),
        game.getImagePath(folder, 'box2d', widget.fileProvider),
        game.getScreenshotPath(folder, widget.fileProvider),
      ];
      for (final path in paths) {
        _fileExistsCache.remove(path);
        _imageSizeCache.remove(path);
      }
    }
  }

  void _initializeGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: _navigateUp,
      onNavigateDown: _navigateDown,
      onNavigateLeft: _navigateLeft,
      onNavigateRight: _navigateRight,
      onSelectItem: widget.onPlay,
      onBack: widget.onBack,
      onFavorite: widget.onFavorite,
      onXButton: widget.onRandom,
      onSettings: widget.onSettings,
    );
  }

  @override
  void dispose() {
    _cardSizeLabelTimer?.cancel();
    _achievementsDebounce?.cancel();
    _cardSizeLabel.dispose();
    GamepadNavigationManager.popLayer('games_grid');
    _gamepadNav.dispose();
    super.dispose();
  }

  int get _cols => _crossAxisCount.clamp(1, 10);

  void _navigateUp() {
    _moveSelection(
      gridMoveUp(
        index: _selectedIndex,
        columns: _cols,
        itemCount: widget.games.length,
      ),
    );
  }

  void _navigateDown() {
    _moveSelection(
      gridMoveDown(
        index: _selectedIndex,
        columns: _cols,
        itemCount: widget.games.length,
      ),
    );
  }

  void _navigateLeft() {
    _moveSelection(
      gridMoveLeft(
        index: _selectedIndex,
        columns: _cols,
        itemCount: widget.games.length,
      ),
    );
  }

  void _navigateRight() {
    _moveSelection(
      gridMoveRight(
        index: _selectedIndex,
        columns: _cols,
        itemCount: widget.games.length,
      ),
    );
  }

  void _moveSelection(int newIndex) {
    if (widget.games.isEmpty) return;
    setState(() {
      _selectedIndex = newIndex.clamp(0, widget.games.length - 1);
      _updateFastNav();
    });
    _onSelectionChanged();
    SfxService().playNavSound();
  }

  void _onSelectionChanged() {
    if (_selectedIndex < widget.games.length) {
      widget.onGameSelected(widget.games[_selectedIndex]);
      _scheduleAchievementsLoad();
    }
  }

  void _updateFastNav() {
    final now = DateTime.now();
    _isNavigatingFast =
        _lastNavTime != null &&
        now.difference(_lastNavTime!) < _fastNavThreshold;
    _lastNavTime = now;
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
    final game = widget.games[_selectedIndex.clamp(0, widget.games.length - 1)];

    if (!_hasRetroAchievementsFor(game)) {
      if (mounted) {
        setState(() {
          _currentGameInfo = null;
          _isLoadingAchievements = false;
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _isLoadingAchievements = true);
    }
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
    final game = widget.games[_selectedIndex.clamp(0, widget.games.length - 1)];
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

  @override
  Widget build(BuildContext context) {
    if (widget.games.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.videogame_asset_rounded,
              size: 64.r,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
            ),
            SizedBox(height: 16.r),
            Text(
              AppLocale.selectAGame.getString(context),
              style: TextStyle(
                fontSize: 18.r,
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final theme = Theme.of(context);
                  final fp = widget.fileProvider;

                  // Single source of truth for the grid's outer insets —
                  // consumed by BOTH the geometry and the scroll padding, so
                  // the cards and the selector always share one coordinate
                  // space and cannot drift apart.
                  final padL = 60.0.r;
                  final padR = 16.0.r;
                  final padT = 12.0.r;
                  final padB = 80.0.r;

                  final geometry = _geometryFor(
                    constraints.maxWidth - padL - padR,
                  );
                  final targetWidth = (geometry.cardWidth * 1.5).toInt();

                  return Listener(
                    onPointerDown: _handlePointerDown,
                    onPointerMove: _handlePointerMove,
                    onPointerUp: _handlePointerUp,
                    onPointerCancel: _handlePointerCancel,
                    behavior: HitTestBehavior.translucent,
                    child: Stack(
                      children: [
                        SelectionGrid(
                          geometry: geometry,
                          padding: EdgeInsets.only(
                            left: padL,
                            right: padR,
                            top: padT,
                            bottom: padB,
                          ),
                          selectedIndex: _selectedIndex,
                          revision: _gridRevision,
                          isNavigatingFast: _isNavigatingFast,
                          // On a discontinuous layout change (density or card
                          // style) the highlight re-creates and jumps to the
                          // new rect instead of sliding across the screen.
                          highlightKey: ValueKey(
                            'games_grid_highlight_${geometry.columns}_$_isFanart',
                          ),
                          itemBuilder: (context, index, cellSize) {
                            _ensureDims(index);
                            return _buildCard(index, fp, targetWidth, theme);
                          },
                        ),
                        ValueListenableBuilder<String?>(
                          valueListenable: _cardSizeLabel,
                          builder: (context, label, child) => AnimatedOpacity(
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
                                          color: theme.colorScheme.primary
                                              .withValues(alpha: 0.9),
                                          borderRadius: BorderRadius.circular(
                                            24.r,
                                          ),
                                        ),
                                        child: Text(
                                          label,
                                          style: TextStyle(
                                            color: theme.colorScheme.onPrimary,
                                            fontSize: 18.r,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 2.r,
                                          ),
                                        ),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            GameViewFooter(
              game: widget
                  .games[_selectedIndex.clamp(0, widget.games.length - 1)],
              onPlay: widget.onPlay,
              hasRetroAchievements:
                  widget.games.isNotEmpty &&
                  _hasRetroAchievementsFor(
                    widget.games[_selectedIndex.clamp(
                      0,
                      widget.games.length - 1,
                    )],
                  ),
              isLoadingAchievements: _isLoadingAchievements,
              currentGameInfo: _currentGameInfo,
              onShowAchievements: _showAchievementsDialog,
            ),
          ],
        ),
        Positioned(
          top: 12.r,
          left: 12.r,
          child: GameActionButtons(
            system: widget.system,
            selectedGame: widget.games.isNotEmpty
                ? widget.games[_selectedIndex.clamp(0, widget.games.length - 1)]
                : null,
            onBack: widget.onBack,
            onFavorite: widget.onFavorite,
            onRandom: widget.onRandom,
            onSettings: widget.onSettings ?? () {},
          ),
        ),
      ],
    );
  }

  // ---- Card builders (one per card style) ----

  Widget _buildCard(
    int index,
    FileProvider fp,
    int targetWidth,
    ThemeData theme,
  ) {
    final game = widget.games[index];
    if (_isFanart) {
      return _buildFanartGridCard(index, game, theme);
    }
    return _buildBox2dGridCard(index, game, fp, targetWidth, theme);
  }

  Widget _buildBox2dGridCard(
    int index,
    GameModel game,
    FileProvider fp,
    int targetWidth,
    ThemeData theme,
  ) {
    final box2dPath = game.getImagePath(_folderForGame(game), 'box2d', fp);
    final aspectRatio = _box2dAspectRatio(index);

    return GestureDetector(
      key: ValueKey('game_${game.romname}'),
      onTap: () {
        setState(() => _selectedIndex = index);
        widget.onGameSelected(game);
        SfxService().playNavSound();
        _scheduleAchievementsLoad();
      },
      child: RepaintBoundary(
        child: Padding(
          padding: EdgeInsets.all(2.r),
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius:
                  Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
                  BorderRadius.circular(14.r),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
                width: 1.r,
              ),
            ),
            child: ClipRRect(
              borderRadius:
                  Theme.of(context).extension<CornerRadii>()?.radiusInternal ??
                  BorderRadius.circular(9.r),
              child: InkWell(
                canRequestFocus: false,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                child: Padding(
                  padding: EdgeInsets.all(4.r),
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: ClipRRect(
                      borderRadius:
                          Theme.of(
                            context,
                          ).extension<CornerRadii>()?.radiusInternal ??
                          BorderRadius.circular(9.r),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.file(
                            File(box2dPath),
                            key: ValueKey('box2d_${game.romname}'),
                            fit: BoxFit.cover,
                            cacheWidth: 384,
                            gaplessPlayback: true,
                            errorBuilder: (ctx, e, s) =>
                                _buildFallbackCard(game, theme),
                          ),
                          if (game.isFavorite == true)
                            Positioned(
                              top: 4.r,
                              right: 4.r,
                              child: Container(
                                width: 22.r,
                                height: 22.r,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  Symbols.favorite_rounded,
                                  size: 12.r,
                                  color: Colors.redAccent,
                                ),
                              ),
                            ),
                          if (widget.scrapingGameRomnames.contains(
                            game.romname,
                          ))
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScrapeProgress(GameModel game) {
    final radii = Theme.of(context).extension<CornerRadii>() ?? CornerRadii.m();
    final progress = widget.scrapeProgress[game.romname] ?? 0.0;
    return Container(
      height: 20.r,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.only(
          bottomLeft: radii.radiusInternal.bottomLeft,
          bottomRight: radii.radiusInternal.bottomRight,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8.r),
      child: Row(
        children: [
          Icon(Symbols.search_rounded, size: 10.r, color: Colors.white70),
          SizedBox(width: 4.r),
          Expanded(
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white24,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          SizedBox(width: 4.r),
          Text(
            '${(progress * 100).toInt()}%',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 9.r,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFanartGridCard(int index, GameModel game, ThemeData theme) {
    final fanartPath = _fanartPath(index);
    final screenshotPath = _screenshotPath(index);
    final hasFanart = _fileExists(fanartPath);
    final hasScreenshot = !hasFanart && _fileExists(screenshotPath);
    final bgPath = hasFanart
        ? fanartPath
        : (hasScreenshot ? screenshotPath : '');

    return GestureDetector(
      key: ValueKey('game_${game.romname}'),
      onTap: () {
        setState(() => _selectedIndex = index);
        widget.onGameSelected(game);
        SfxService().playNavSound();
        _scheduleAchievementsLoad();
      },
      child: RepaintBoundary(
        child: Padding(
          padding: EdgeInsets.all(2.r),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius:
                  Theme.of(context).extension<CornerRadii>()?.radiusExternal ??
                  BorderRadius.circular(14.r),
              border: Border.all(
                color: Theme.of(context).colorScheme.outline,
                width: 1.r,
              ),
            ),
            child: ClipRRect(
              borderRadius:
                  Theme.of(context).extension<CornerRadii>()?.radiusInternal ??
                  BorderRadius.circular(9.r),
              child: InkWell(
                canRequestFocus: false,
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                child: Padding(
                  padding: EdgeInsets.all(4.r),
                  child: Column(
                    children: [
                      AspectRatio(
                        aspectRatio: 1,
                        child: ClipRRect(
                          borderRadius:
                              Theme.of(
                                context,
                              ).extension<CornerRadii>()?.radiusInternal ??
                              BorderRadius.circular(9.r),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (bgPath.isNotEmpty)
                                Image.file(
                                  File(bgPath),
                                  key: ValueKey('fanart_bg_${game.romname}'),
                                  fit: BoxFit.cover,
                                  cacheWidth: 384,
                                  gaplessPlayback: true,
                                  errorBuilder: (ctx, e, s) =>
                                      _buildFallbackCard(game, theme),
                                )
                              else
                                _buildFallbackCard(game, theme),
                              if (game.isFavorite == true)
                                Positioned(
                                  top: 4.r,
                                  right: 4.r,
                                  child: Container(
                                    width: 22.r,
                                    height: 22.r,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(
                                        alpha: 0.6,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Symbols.favorite_rounded,
                                      size: 12.r,
                                      color: Colors.redAccent,
                                    ),
                                  ),
                                ),
                              if (widget.scrapingGameRomnames.contains(
                                game.romname,
                              ))
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
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
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
              Icons.videogame_asset_rounded,
              size: 32.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            SizedBox(height: 4.r),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 4.r),
              child: Text(
                GameUtils.formatGameName(
                  game.name.isNotEmpty ? game.name : game.romname,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 7.r,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
