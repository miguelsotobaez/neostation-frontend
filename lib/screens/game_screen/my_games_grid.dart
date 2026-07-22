import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/utils/game_utils.dart';
import 'package:neostation/widgets/game_view_mode_dropdown.dart';
import 'package:neostation/widgets/game_action_buttons.dart';
import 'package:neostation/services/game_legend_visibility.dart';
import 'package:neostation/sync/sync_manager.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/repositories/game_repository.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/widgets/game_view_footer.dart';
import 'package:neostation/constants/system_folder_names.dart';
import 'package:neostation/models/retro_achievements_game_info.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/services/retro_achievements_helper.dart';
import 'package:neostation/screens/game_screen/game_details_card/dialogs/game_achievements_dialog.dart';

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
  final VoidCallback? onScrape;
  final Set<String> scrapingGameRomnames;
  final Map<String, double> scrapeProgress;

  /// No-op stub retained for API compatibility with the current scraping tab.
  /// This pre-#188 grid keeps no static artwork caches; the Flutter image
  /// cache is evicted separately by the caller.
  static void evictArtworkCaches(Iterable<String> paths) {}

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
    this.onScrape,
    this.scrapingGameRomnames = const {},
    this.scrapeProgress = const {},
  });

  @override
  State<GamesGrid> createState() => _GamesGridState();
}

class _GamesGridState extends State<GamesGrid>
    with SingleTickerProviderStateMixin {
  late GamepadNavigation _gamepadNav;
  final ScrollController _scrollController = ScrollController();
  int _selectedIndex = 0;
  int _crossAxisCount = 5;
  bool _isNavigatingFast = false;

  // RetroAchievements info for the selected game (shown in the footer pill).
  GameInfoAndUserProgress? _currentGameInfo;
  bool _isLoadingAchievements = false;
  String? _achievementsTargetRomname;
  // Loading RA (plus its setState churn) on every gamepad move floods the UI
  // thread during fast navigation. Debounce so it loads once selection settles.
  Timer? _achievementsDebounce;
  static const Duration _achievementsSettleDelay = Duration(milliseconds: 280);
  DateTime? _lastNavTime;
  static const Duration _fastNavThreshold = Duration(milliseconds: 150);

  // Debounced "settled" selection that drives the footer pill + action-button
  // legend. Rebuilding that chrome on every fast-nav move floods the UI thread
  // (measured: ~18% severe frame drops vs ~11% without it). Instead we only
  // advance _settledIndex once rapid navigation stops, and memoize the built
  // chrome by signature so build() returns identical instances during a burst
  // (Flutter then skips those subtrees). The highlight cursor still tracks
  // _selectedIndex every move for immediate feedback.
  int _settledIndex = 0;
  Timer? _settleTimer;
  static const Duration _chromeSettleDelay = Duration(milliseconds: 160);
  String? _chromeSig;
  Widget? _chromeFooter;
  Widget? _chromeLegend;

  // Memoized grid rows. buildRow→_buildCard is a pure function of layout
  // (`_layoutGen`), `targetWidth`, `theme`, and per-card favorite/scrape state —
  // it never reads `_selectedIndex` (selection is drawn by the Positioned cursor
  // overlay). So on a steady scroll the rows are identical across a settle /
  // RA-load / legend-animating setState, yet an un-memoized SliverList.builder
  // rebuilds all ~50 visible cards each time (profile-build VM timeline measured
  // ~5 full-viewport rebuilds per scroll = 22–31 ms UI-thread BUILD spikes; the
  // raster pipeline stays <5 ms). Cache built rows by index and gate on a cheap
  // signature so those setStates return identical Row instances and Flutter
  // skips the whole subtree. `_layoutGen` bumps whenever _positionCards actually
  // re-runs (width/reflow/dim-reload), so the legend reflow still rebuilds while
  // steady scroll does not. The cache is also cleared in didUpdateWidget when the
  // game set or scrape state changes (favorite stars / scrape progress overlays).
  int _layoutGen = 0;
  final Map<int, Widget> _rowCache = {};
  String? _rowCacheSig;

  // Selection cursor. The border follows the *selected card's real rendered box*
  // via a per-card LayerLink + CompositedTransformFollower, so it tracks the card
  // through scrolling AND the Select+B reflow with zero manual coordinate math.
  // This is what makes it correct at any scroll depth: a global-model overlay
  // (selRect.top - scrollOffset) drifts because the culled SliverList doesn't
  // re-lay off-screen rows when the cards grow, so its scroll accounting diverges
  // from the model by an amount that accumulates per off-screen row. The follower
  // sidesteps that entirely — it reads the leader layer's actual position. Links
  // are created lazily per card index (only cards that get built get one).
  final Map<int, LayerLink> _cardLinks = {};
  // Cross-card glide: on a selection change the follower snaps to the new card,
  // and this controller eases the border from the old card's rect to the new one
  // (Transform + size) so the cursor still slides between cards. At rest (value 1)
  // the border sits exactly on the followed card.
  late final AnimationController _cursorGlide;
  double _glideFromLeft = 0;
  double _glideFromTop = 0;
  double _glideFromWidth = 0;
  double _glideFromHeight = 0;

  // Layout
  List<_CardRect> _cardRects = [];
  List<_RowInfo> _rows = [];
  double _cardWidth = 0;
  double _spX = 0;
  double _spY = 0;
  double? _lastLayoutWidth;
  int? _lastLayoutCols;
  bool? _lastIsFanart;

  // Per-card height/width ratio (aspect), which is INDEPENDENT of the card
  // width. Measuring it is the expensive part of layout (file-header reads +
  // string parsing per game), so it is cached here and only recomputed when the
  // game set / column count / fanart mode / loaded dimensions change — never on
  // a mere width change. That lets the Select+B reflow animate the width with
  // cheap per-frame arithmetic instead of re-measuring every card each frame.
  List<double> _cardHOverW = [];
  bool _needsMeasure = true;

  // Image dimension cache
  static final Map<String, Size?> _imageSizeCache = {};

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

  String _wheelsPath(int index) {
    final game = widget.games[index];
    return game.getImagePath(
      _folderForGame(game),
      'wheels',
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

  /// Height/width ratio for a card, INDEPENDENT of the current card width.
  /// This is the expensive lookup (DB string parse or image-header read) that
  /// [_measureCards] caches into [_cardHOverW]. Note `_cardHeightFor(i)` equals
  /// `_cardWidth * _heightRatioFor(i)`.
  double _heightRatioFor(int index) {
    if (_isFanart) return 1.0;

    final game = widget.games[index];
    // 1. From DB
    if (game.box2dAspectRatio != null && game.box2dAspectRatio!.isNotEmpty) {
      final parts = game.box2dAspectRatio!.split('/');
      if (parts.length == 2) {
        final w = double.tryParse(parts[0]);
        final h = double.tryParse(parts[1]);
        if (w != null && h != null && w > 0 && h > 0) {
          return h / w;
        }
      }
    }
    // 2. From file header
    final path = _box2dPath(index);
    final size = _readImageSize(path);
    if (size != null && size.width > 0 && size.height > 0) {
      // Save to DB for next time
      final ratio = '${size.width.toInt()}/${size.height.toInt()}';
      _scheduleAspectRatioSave(game, ratio);
      return size.height / size.width;
    }
    return 1.0; // 1:1 fallback
  }

  /// Measures every card's aspect ratio into [_cardHOverW]. This is the only
  /// O(n) width-INDEPENDENT pass and is deliberately kept out of the per-frame
  /// path so a width animation (Select+B reflow) never re-reads image headers.
  void _measureCards() {
    final n = widget.games.length;
    _cardHOverW = List<double>.filled(n, 1.0);
    _loadedDims.clear();
    if (!_isFanart) {
      for (int i = 0; i < n; i++) {
        _cardHOverW[i] = _heightRatioFor(i);
        if (_imageSizeCache.containsKey(_box2dPath(i))) _loadedDims.add(i);
      }
    }
    _needsMeasure = false;
  }

  // ---- Layout ----
  // Aspect ratios (the costly part) are measured/cached separately; positioning
  // for a given width is cheap arithmetic so it can run every animation frame.

  void _computeLayout(double availableWidth) {
    final measureChanged =
        _needsMeasure ||
        _cardHOverW.length != widget.games.length ||
        _lastIsFanart != _isFanart ||
        _needsDimReload;

    if (!measureChanged &&
        _lastLayoutWidth == availableWidth &&
        _lastLayoutCols == _cols) {
      return;
    }

    if (measureChanged) {
      _measureCards();
      _needsDimReload = false;
    }

    _lastLayoutWidth = availableWidth;
    _lastLayoutCols = _cols;
    _lastIsFanart = _isFanart;

    _positionCards(availableWidth);
  }

  /// Cheap positioning pass: turns cached aspect ratios + a target width into
  /// card rects and row bounds. No image reads, one allocation per card.
  void _positionCards(double availableWidth) {
    final spX = 6.0.r;
    final spY = 6.0.r;
    _spX = spX;
    _spY = spY;

    final totalWidth = availableWidth - 32;
    _cardWidth = (totalWidth - (_cols - 1) * spX) / _cols;
    final n = widget.games.length;
    final rowCount = _cols > 0 ? (n + _cols - 1) ~/ _cols : 0;

    // Reuse the existing buffers when the counts are unchanged (the common case
    // while the reflow animates), mutating rects in place so a width change
    // allocates nothing.
    if (_cardRects.length != n) {
      _cardRects = List.generate(
        n,
        (_) => _CardRect(left: 0, top: 0, width: 0, height: 0),
      );
    }
    if (_rows.length != rowCount) {
      _rows = List.generate(
        rowCount,
        (_) => _RowInfo(topY: 0, height: 0, startIndex: 0, count: 0),
      );
    }

    double y = 0;
    int i = 0;
    int r = 0;
    while (i < n) {
      final end = (i + _cols).clamp(0, n);
      double maxH = 0;
      for (int idx = i; idx < end; idx++) {
        final h = _cardHOverW[idx] * _cardWidth;
        if (h > maxH) maxH = h;
      }
      final row = _rows[r];
      row.topY = y;
      row.height = maxH;
      row.startIndex = i;
      row.count = end - i;
      for (int idx = i; idx < end; idx++) {
        final col = idx % _cols;
        final h = _cardHOverW[idx] * _cardWidth;
        final rect = _cardRects[idx];
        rect.left = col * (_cardWidth + spX);
        rect.top = y + (maxH + spY - h) / 2;
        rect.width = _cardWidth;
        rect.height = h;
      }
      y += maxH + spY;
      i = end;
      r++;
    }

    // Card rects/rows just changed → any memoized row widgets are stale.
    // Bumping the generation invalidates the row cache on the next build (see
    // _rowCache). This runs on every reflow frame (intended) but NOT during a
    // steady scroll, where _computeLayout early-returns without calling us.
    _layoutGen++;
  }

  // Lazy dimension loading for newly visible cards
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
    _settledIndex = _selectedIndex;
    _cursorGlide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      value: 1, // start settled on the initial card (no glide)
    );
    _updateCrossAxisCount();
    _initializeGamepad();
    GameLegendVisibility.hidden.addListener(_onLegendVisibilityChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _gamepadNav.initialize();
        GamepadNavigationManager.pushLayer(
          'games_grid',
          onActivate: () => _gamepadNav.activate(),
          onDeactivate: () => _gamepadNav.deactivate(),
        );
        _ensureSelectedVisible();
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
    // Theme / MediaQuery / ScreenUtil may have changed; drop the memoized
    // chrome so it rebuilds with fresh sizing on the next build.
    _chromeSig = null;
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
        _lastLayoutWidth = null;
        _showCardSizeLabel(newSize);
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _ensureSelectedVisible();
        });
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
    final prevCols = _crossAxisCount;
    _updateCrossAxisCount();
    if (widget.games != oldWidget.games || _crossAxisCount != prevCols) {
      _lastLayoutWidth = null;
      // Aspect-ratio cache is keyed by index; a changed game set (even at the
      // same length) must be re-measured.
      if (widget.games != oldWidget.games) _needsMeasure = true;
    }
    // Row memoization depends on per-card favorite/scrape state, which arrives
    // via these props. Any change means the cached rows may be stale, so drop
    // them (a changed game set / cols also invalidates via _layoutGen, but the
    // scrape props do not touch layout — clear explicitly).
    if (widget.games != oldWidget.games ||
        widget.scrapingGameRomnames != oldWidget.scrapingGameRomnames ||
        widget.scrapeProgress != oldWidget.scrapeProgress) {
      _rowCache.clear();
    }
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _selectedIndex = widget.selectedIndex.clamp(
        0,
        (widget.games.length - 1).clamp(0, 999999),
      );
      // External selection change (not a local nav): snap the cursor to the new
      // card rather than gliding from a possibly-unrelated previous position.
      _cursorGlide.value = 1;
      if (mounted && _scrollController.hasClients) {
        _ensureSelectedVisible();
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
      onXButton: () {
        try {
          GameViewModeDropdown.globalKey.currentState?.showDropdown();
        } catch (_) {}
      },
      onLeftStickClick: widget.onRandom,
      onSelectButton: widget.onScrape,
      onSelectModifierB: _toggleLegend, // Select + B - Hide/show legend.
      onSettings: widget.onSettings,
    );
  }

  /// Select + B — toggles the (session-global) vertical action-button legend.
  /// When hidden the legend slides off the left edge and the grid reflows into
  /// the 60.r gutter.
  void _toggleLegend() {
    SfxService().playNavSound();
    GameLegendVisibility.toggle();
  }

  /// Reacts to any change of the shared legend flag (this view's chord or a
  /// future external/DB update). Starts the reflow animation; the flag is
  /// cleared in AnimatedPadding.onEnd.
  void _onLegendVisibilityChanged() {
    // Rebuild so AnimatedPadding picks up the new indent target and animates the
    // reflow. The selection cursor needs no special handling here — it follows
    // the selected card's real box via the LayerLink follower, so it stays fitted
    // as the card grows/shrinks with no per-frame coordinate correction.
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cardSizeLabelTimer?.cancel();
    _achievementsDebounce?.cancel();
    _settleTimer?.cancel();
    _cardSizeLabel.dispose();
    GameLegendVisibility.hidden.removeListener(_onLegendVisibilityChanged);
    GamepadNavigationManager.popLayer('games_grid');
    _gamepadNav.dispose();
    _scrollController.dispose();
    _cursorGlide.dispose();
    super.dispose();
  }

  int get _cols => _crossAxisCount.clamp(1, 10);

  void _navigateUp() {
    _navDelta(-_cols);
  }

  void _navigateDown() {
    _navDelta(_cols);
  }

  void _navigateLeft() {
    _navHoriz(-1);
  }

  void _navigateRight() {
    _navHoriz(1);
  }

  void _navDelta(int delta) {
    if (widget.games.isEmpty) return;
    final c = _cols;
    final from = _selectedIndex;
    setState(() {
      int ni = _selectedIndex + delta;
      if (delta < 0 && ni < 0) {
        final col = _selectedIndex % c;
        ni = ((widget.games.length / c).ceil() - 1) * c + col;
        while (ni >= widget.games.length) {
          ni -= c;
        }
        if (ni < 0) ni = _selectedIndex;
      } else if (delta > 0 && ni >= widget.games.length) {
        ni = _selectedIndex % c;
      }
      _selectedIndex = ni.clamp(0, widget.games.length - 1);
      _updateFastNav();
    });
    _beginCursorGlide(from);
    _ensureSelectedVisible();
    _onSelectionChanged();
    SfxService().playNavSound();
  }

  void _navHoriz(int dir) {
    if (widget.games.isEmpty) return;
    final from = _selectedIndex;
    setState(() {
      int ni;
      if (dir < 0) {
        final wrapRight = (_selectedIndex ~/ _cols) * _cols + _cols - 1;
        ni = _selectedIndex % _cols == 0
            ? (wrapRight < widget.games.length - 1
                  ? wrapRight
                  : widget.games.length - 1)
            : _selectedIndex - 1;
      } else {
        final next = _selectedIndex + 1;
        ni = (next % _cols == 0 || next >= widget.games.length)
            ? (_selectedIndex ~/ _cols) * _cols
            : next;
      }
      _selectedIndex = ni.clamp(0, widget.games.length - 1);
      _updateFastNav();
    });
    _beginCursorGlide(from);
    _ensureSelectedVisible();
    _onSelectionChanged();
    SfxService().playNavSound();
  }

  /// Kicks the selection cursor's cross-card glide: snapshot the card we moved
  /// *from* (its rect, before layout changes) and run the controller. The
  /// follower is already re-anchored to the new card on the next build, so the
  /// glide interpolates the border from the old card's box to the new one; at
  /// rest the border sits exactly on the followed card.
  void _beginCursorGlide(int fromIndex) {
    if (fromIndex == _selectedIndex) return;
    if (fromIndex >= 0 && fromIndex < _cardRects.length) {
      final r = _cardRects[fromIndex];
      _glideFromLeft = r.left;
      _glideFromTop = r.top;
      _glideFromWidth = r.width;
      _glideFromHeight = r.height;
      _cursorGlide.duration = Duration(
        milliseconds: _isNavigatingFast ? 120 : 300,
      );
      _cursorGlide.forward(from: 0);
    } else {
      _cursorGlide.value = 1;
    }
  }

  void _onSelectionChanged() {
    if (_selectedIndex < widget.games.length) {
      widget.onGameSelected(widget.games[_selectedIndex]);
    }
    _scheduleAchievementsLoad();
    _scheduleChromeSettle();
  }

  /// Advances the footer/legend's settled selection. A single (slow) move
  /// updates it immediately; during a fast-nav burst it is deferred until
  /// navigation settles, so the expensive chrome isn't rebuilt every frame.
  void _scheduleChromeSettle() {
    _settleTimer?.cancel();
    if (!_isNavigatingFast) {
      if (_settledIndex != _selectedIndex) {
        setState(() => _settledIndex = _selectedIndex);
      }
      return;
    }
    _settleTimer = Timer(_chromeSettleDelay, () {
      if (mounted && _settledIndex != _selectedIndex) {
        setState(() => _settledIndex = _selectedIndex);
      }
    });
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

  /// Debounced entry point for the navigation hot path — coalesces rapid moves
  /// into a single load once the user stops on a game.
  void _scheduleAchievementsLoad() {
    // Reflect the new selection in the footer's RA indicator immediately so
    // fast navigation never shows the previous game's counts while the
    // (debounced) load is pending.
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

  void _updateFastNav() {
    final now = DateTime.now();
    _isNavigatingFast =
        _lastNavTime != null &&
        now.difference(_lastNavTime!) < _fastNavThreshold;
    _lastNavTime = now;
  }

  void _ensureSelectedVisible() {
    if (!_scrollController.hasClients || _cardRects.isEmpty) return;
    final rect = _cardRects[_selectedIndex.clamp(0, _cardRects.length - 1)];
    final viewportH = _scrollController.position.viewportDimension;
    final target = (rect.top - viewportH / 2 + rect.height / 2).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: Duration(milliseconds: _isNavigatingFast ? 220 : 500),
      curve: Curves.easeOutQuart,
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

    _buildSettledChrome();

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              // Indent the grid to clear the vertical legend on the left; the
              // reduced width makes the cards slightly smaller. Select + B hides
              // the legend and animates this indent to 0 so the cards genuinely
              // reflow to fill the reclaimed 60.r. This drives _computeLayout
              // every frame, but only its cheap _positionCards pass runs (aspect
              // ratios are cached in _cardHOverW). The selection cursor needs no
              // special handling during the reflow — it follows the selected
              // card's real box via the LayerLink follower, so it stays fitted as
              // the card grows with zero coordinate math.
              child: AnimatedPadding(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                padding: EdgeInsets.only(
                  left: GameLegendVisibility.hidden.value ? 0 : 60.r,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    _computeLayout(constraints.maxWidth);

                    final theme = Theme.of(context);
                    final fp = widget.fileProvider;
                    // Quantize the decode resolution into buckets so the tiny
                    // per-frame card-width changes during the legend reflow don't
                    // thrash _GameCardImage into re-decoding every card each frame
                    // (it reloads whenever targetWidth changes). Also a general win
                    // for any width change (window resize, card-size cycling).
                    const decodeBucket = 64;
                    final bucketed =
                        ((_cardWidth * 1.5) / decodeBucket).ceil() *
                        decodeBucket;
                    final targetWidth = bucketed < decodeBucket
                        ? decodeBucket
                        : bucketed;

                    final selRect = _selectedIndex < _cardRects.length
                        ? _cardRects[_selectedIndex]
                        : _cardRects.first;

                    // Row-cache gate: when the layout/decode/theme signature is
                    // unchanged, buildRow returns the exact same Row instances it
                    // built last time, so a selection/settle/RA/legend setState
                    // that re-runs build() does NOT rebuild the ~50 visible cards
                    // (Flutter short-circuits identical child widgets). Any real
                    // change (reflow bumps _layoutGen, width change moves
                    // targetWidth, theme flips) rotates the signature and rebuilds.
                    final rowSig =
                        '$_layoutGen|$targetWidth|${theme.brightness.index}';
                    if (rowSig != _rowCacheSig) {
                      _rowCacheSig = rowSig;
                      _rowCache.clear();
                    }

                    Widget buildRow(BuildContext ctx, int rowIndex) {
                      final cached = _rowCache[rowIndex];
                      if (cached != null) return cached;
                      final row = _rows[rowIndex];
                      final cards = <Widget>[];
                      for (int j = 0; j < row.count; j++) {
                        final idx = row.startIndex + j;
                        final rect = _cardRects[idx];
                        _ensureDims(idx);
                        final card = _buildCard(
                          idx,
                          rect,
                          fp,
                          targetWidth,
                          theme,
                        );
                        cards.add(
                          SizedBox(
                            width: rect.width,
                            height: rect.height,
                            // Anchor a per-card LayerLink so the selection cursor
                            // can follow this card's real rendered box. Links are
                            // cached per index (stable identity across row-cache
                            // rebuilds); only built cards get one.
                            child: CompositedTransformTarget(
                              link: _cardLinks.putIfAbsent(
                                idx,
                                () => LayerLink(),
                              ),
                              child: card,
                            ),
                          ),
                        );
                      }
                      final built = SizedBox(
                        height: row.height + _spY,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: _interleaveSpacing(cards, _spX),
                        ),
                      );
                      _rowCache[rowIndex] = built;
                      return built;
                    }

                    final borderColor = theme.colorScheme.secondary;
                    final selLink = _cardLinks[_selectedIndex];

                    return Listener(
                      onPointerDown: _handlePointerDown,
                      onPointerMove: _handlePointerMove,
                      onPointerUp: _handlePointerUp,
                      onPointerCancel: _handlePointerCancel,
                      behavior: HitTestBehavior.translucent,
                      child: Stack(
                        children: [
                          CustomScrollView(
                            controller: _scrollController,
                            slivers: [
                              SliverPadding(
                                padding: EdgeInsets.only(
                                  top: 12,
                                  bottom: 80,
                                  left: 16,
                                  right: 16,
                                ),
                                sliver: SliverList.builder(
                                  itemCount: _rows.length,
                                  itemBuilder: buildRow,
                                ),
                              ),
                            ],
                          ),
                          // Selection cursor. It follows the selected card's real
                          // rendered box via a LayerLink, so it tracks the card
                          // through scrolling AND the Select+B reflow (the card
                          // grows, the leader layer moves, the border moves with it)
                          // with no scroll-offset math — which is what kept the old
                          // overlay drifting a row too low a few rows down. The
                          // cross-card glide is driven by _cursorGlide: on selection
                          // change the follower snaps to the new card and the border
                          // eases from the old card's rect (Transform + size) to a
                          // snug fit on the new one (translate 0, size == selRect).
                          // Clip the cursor to the grid viewport. The follower's
                          // render box is border-sized and sits at the Stack's
                          // top-left; it only moves to the leader at composite time
                          // via a layer transform, so the Stack's overflow-based
                          // clip never fires and the border would otherwise paint
                          // over the footer when a card scrolls past the bottom edge
                          // during fast scrolling. An explicit ClipRect always
                          // clips, regardless of the follower's reported size. The
                          // Align fills the ClipRect (so it clips at the grid
                          // bounds) while passing LOOSE constraints to the
                          // follower — otherwise Positioned.fill's tight grid-sized
                          // constraints would stretch the border Container to fill
                          // the whole grid.
                          if (selLink != null)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: ClipRect(
                                  child: Align(
                                    alignment: Alignment.topLeft,
                                    child: CompositedTransformFollower(
                                      link: selLink,
                                      showWhenUnlinked: false,
                                      targetAnchor: Alignment.topLeft,
                                      followerAnchor: Alignment.topLeft,
                                      child: AnimatedBuilder(
                                        animation: _cursorGlide,
                                        builder: (_, _) {
                                          final t = Curves.easeOutQuart
                                              .transform(_cursorGlide.value);
                                          final inv = 1 - t;
                                          final dx =
                                              (_glideFromLeft - selRect.left) *
                                              inv;
                                          final dy =
                                              (_glideFromTop - selRect.top) *
                                              inv;
                                          final w =
                                              _glideFromWidth +
                                              (selRect.width -
                                                      _glideFromWidth) *
                                                  t;
                                          final h =
                                              _glideFromHeight +
                                              (selRect.height -
                                                      _glideFromHeight) *
                                                  t;
                                          return Transform.translate(
                                            offset: Offset(dx, dy),
                                            child: Container(
                                              width: w,
                                              height: h,
                                              decoration: BoxDecoration(
                                                border: Border.all(
                                                  color: borderColor,
                                                  width: 4.r,
                                                ),
                                                borderRadius:
                                                    BorderRadius.circular(12.r),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
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
                                              color:
                                                  theme.colorScheme.onPrimary,
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
            ),
            // Footer pill is driven by the debounced settled selection and
            // memoized (see _buildSettledChrome) so it is not rebuilt on every
            // fast-nav frame.
            _chromeFooter!,
          ],
        ),
        // Vertical action-button legend (shared with the game list view);
        // also memoized on the settled selection. Select + B slides it off the
        // left edge (in sync with the grid's Transform slide).
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          top: 12.r,
          left: GameLegendVisibility.hidden.value ? -60.r : 12.r,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: GameLegendVisibility.hidden.value ? 0.0 : 1.0,
            child: _chromeLegend!,
          ),
        ),
      ],
    );
  }

  /// (Re)builds the footer pill + action-button legend only when the settled
  /// selection or its achievement/favorite state changes. During a fast-nav
  /// burst the signature is stable, so build() reuses the same widget
  /// instances and Flutter skips these (relatively expensive) subtrees.
  void _buildSettledChrome() {
    final settledGame =
        widget.games[_settledIndex.clamp(0, widget.games.length - 1)];
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
    );
    // Positioning/visibility is applied at the Stack level (AnimatedPositioned)
    // so Select + B can animate it without invalidating this memoized subtree.
    _chromeLegend = Consumer<SyncManager>(
      builder: (context, syncManager, child) => GameActionButtons(
        system: widget.system,
        selectedGame: settledGame,
        syncProvider: syncManager.active,
        onBack: widget.onBack,
        onFavorite: widget.onFavorite,
        onViewMode: () =>
            GameViewModeDropdown.globalKey.currentState?.showDropdown(),
        onSettings: widget.onSettings ?? () {},
        onRandom: widget.onRandom,
        onScrape: widget.onScrape,
      ),
    );
  }

  List<Widget> _interleaveSpacing(List<Widget> items, double spacing) {
    if (items.isEmpty) return items;
    final result = <Widget>[items.first];
    for (int i = 1; i < items.length; i++) {
      result.add(SizedBox(width: spacing));
      result.add(items[i]);
    }
    return result;
  }

  Widget _buildCard(
    int index,
    _CardRect rect,
    FileProvider fp,
    int targetWidth,
    ThemeData theme,
  ) {
    final game = widget.games[index];

    if (_isFanart) {
      return _buildFanartGridCard(index, rect, game, theme);
    }

    final box2dPath = game.getImagePath(_folderForGame(game), 'box2d', fp);

    return GestureDetector(
      key: ValueKey('game_${game.romname}'),
      onTap: () {
        final from = _selectedIndex;
        setState(() {
          _selectedIndex = index;
          _settledIndex = index; // discrete tap: update chrome immediately
        });
        _beginCursorGlide(from);
        _settleTimer?.cancel();
        widget.onGameSelected(game);
        _scheduleAchievementsLoad();
        SfxService().playNavSound();
      },
      child: RepaintBoundary(
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12.r),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 2.r,
                    offset: Offset(2.r, 2.r),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: _GameCardImage(
                key: ValueKey('img_${game.romname}'),
                box2dPath: box2dPath,
                game: game,
                targetWidth: targetWidth,
              ),
            ),
            if (game.isFavorite == true)
              Positioned(
                top: 6.r,
                right: 6.r,
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
      height: 20.r,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12.r)),
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

  Widget _buildFanartGridCard(
    int index,
    _CardRect rect,
    GameModel game,
    ThemeData theme,
  ) {
    final fanartPath = _fanartPath(index);
    final screenshotPath = _screenshotPath(index);
    final wheelsPath = _wheelsPath(index);
    final hasFanart = File(fanartPath).existsSync();
    final hasScreenshot = !hasFanart && File(screenshotPath).existsSync();
    final hasWheel = File(wheelsPath).existsSync();
    final bgPath = hasFanart
        ? fanartPath
        : (hasScreenshot ? screenshotPath : '');

    return GestureDetector(
      key: ValueKey('game_${game.romname}'),
      onTap: () {
        final from = _selectedIndex;
        setState(() {
          _selectedIndex = index;
          _settledIndex = index; // discrete tap: update chrome immediately
        });
        _beginCursorGlide(from);
        _settleTimer?.cancel();
        widget.onGameSelected(game);
        _scheduleAchievementsLoad();
        SfxService().playNavSound();
      },
      child: RepaintBoundary(
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 2.r,
                offset: Offset(2.r, 2.r),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12.r),
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (bgPath.isNotEmpty)
                  Image.file(
                    File(bgPath),
                    key: ValueKey('fanart_bg_${game.romname}'),
                    fit: BoxFit.cover,
                    cacheWidth: 388,
                    errorBuilder: (ctx, e, s) =>
                        _buildFallbackCard(game, theme),
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
                          Colors.black.withValues(alpha: 0.5),
                          Colors.black.withValues(alpha: 0.85),
                        ],
                        stops: const [0.5, 0.75, 1.0],
                      ),
                    ),
                  ),
                if (hasWheel)
                  Positioned(
                    left: 10.r,
                    right: 10.r,
                    bottom: 5.r,
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 6.r,
                        vertical: 4.r,
                      ),
                      child: Image.file(
                        File(wheelsPath),
                        key: ValueKey('wheel_${game.romname}'),
                        fit: BoxFit.contain,
                        cacheWidth: 388,
                        errorBuilder: (ctx, e, s) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                if (game.isFavorite == true)
                  Positioned(
                    top: 6.r,
                    right: 6.r,
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

// ---- Card image with lazy loading ----
class _GameCardImage extends StatefulWidget {
  final String box2dPath;
  final GameModel game;
  final int targetWidth;
  const _GameCardImage({
    super.key,
    required this.box2dPath,
    required this.game,
    required this.targetWidth,
  });
  @override
  State<_GameCardImage> createState() => _GameCardImageState();
}

class _GameCardImageState extends State<_GameCardImage> {
  // Process-wide cache of box2d-path existence. Fast dpad scroll recreates a
  // card's `_GameCardImage` every time it re-enters the viewport (keyed by
  // romname), and each creation used to fire a synchronous `existsSync()`
  // syscall on the UI thread. Caching the boolean keeps re-scroll off the
  // filesystem entirely.
  static final Map<String, bool> _existsCache = {};

  ImageProvider? _imageProvider;
  bool _exists = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    // Pre-first-build: resolve synchronously without a redundant setState.
    _computeResolve();
  }

  @override
  void didUpdateWidget(covariant _GameCardImage old) {
    super.didUpdateWidget(old);
    if (old.box2dPath != widget.box2dPath ||
        old.targetWidth != widget.targetWidth) {
      _checked = false;
      _exists = false;
      _imageProvider = null;
      _resolve();
    }
  }

  /// Populate `_exists`/`_imageProvider` for the current box2d path. Returns
  /// true if any field changed. Callers decide whether a setState is needed
  /// (initState resolves before the first build, so it skips setState).
  bool _computeResolve() {
    if (_checked) return false;
    final path = widget.box2dPath;
    final exists = _existsCache[path] ??= File(path).existsSync();
    _checked = true;
    _exists = exists;
    if (exists) {
      _imageProvider = ResizeImage(
        FileImage(File(path)),
        width: widget.targetWidth,
        allowUpscaling: false,
      );
    }
    return true;
  }

  void _resolve() {
    if (!_computeResolve() || !mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_checked) return const SizedBox.shrink();
    if (_exists && _imageProvider != null) {
      return Image(
        image: _imageProvider!,
        fit: BoxFit.contain,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          return AnimatedOpacity(
            opacity: frame == null ? 0 : 1,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeIn,
            child: child,
          );
        },
        errorBuilder: (c, e, s) => _Placeholder(game: widget.game),
      );
    }
    return _Placeholder(game: widget.game);
  }
}

class _Placeholder extends StatelessWidget {
  final GameModel game;
  const _Placeholder({required this.game});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.videogame_asset_rounded,
              size: 32.r,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.4),
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
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Mutable so [_positionCards] can update a reused buffer in place — a width
// change (the Select+B reflow) then allocates nothing per frame.
class _RowInfo {
  double topY;
  double height;
  int startIndex;
  int count;
  _RowInfo({
    required this.topY,
    required this.height,
    required this.startIndex,
    required this.count,
  });
}

class _CardRect {
  double left, top, width, height;
  _CardRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });
}
