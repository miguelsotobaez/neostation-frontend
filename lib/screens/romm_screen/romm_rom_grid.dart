import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../models/romm_rom.dart';
import '../../providers/romm_provider.dart';
import '../../providers/sqlite_config_provider.dart';
import '../../services/gamepad/gamepad_navigation_manager.dart';
import '../../services/sfx_service.dart';
import '../../utils/gamepad_nav.dart';
import '../app_screen.dart';
import 'romm_cover_aspect.dart';
import 'romm_rom_card.dart';

/// Artwork grid for the RomM browser's ROM view.
///
/// The remote sibling of the local library's `GamesGrid`: same variable-height
/// row engine (cards keep their artwork's own aspect, rows are as tall as their
/// tallest card), same in-cell selection border, same card-size cycling off
/// `gameGridColumns`, and the same debounced "settled selection" that keeps the
/// footer and legend out of the fast-navigation hot path.
///
/// What differs is the data: covers are fetched over the network rather than
/// read off disk (see [RommCoverAspect]) and the library is paged, so moving
/// past the last loaded row asks for the next page instead of wrapping.
class RommRomGrid extends StatefulWidget {
  final RommProvider provider;
  final List<RommRom> roms;
  final List<String> romFolders;

  /// Index to open on, so the selection survives a view-mode switch.
  final int initialIndex;
  final ValueChanged<int> onIndexChanged;

  /// A / the on-tile control — start (or cancel) the ROM's download.
  final ValueChanged<RommRom> onConfirm;
  final ValueChanged<RommRom> onCancel;
  final VoidCallback onBack;

  /// X — cycles grid ↔ list.
  final VoidCallback onToggleView;

  /// Y — starts (or cancels) a bulk sync of the open platform/collection.
  final VoidCallback onSyncAll;

  /// Footer for the settled selection, built by the host so it keeps ownership
  /// of the open platform / collection context.
  final Widget Function(RommRom? focused) footerBuilder;

  const RommRomGrid({
    super.key,
    required this.provider,
    required this.roms,
    required this.romFolders,
    required this.initialIndex,
    required this.onIndexChanged,
    required this.onConfirm,
    required this.onCancel,
    required this.onBack,
    required this.onToggleView,
    required this.onSyncAll,
    required this.footerBuilder,
  });

  @override
  State<RommRomGrid> createState() => _RommRomGridState();
}

class _RommRomGridState extends State<RommRomGrid> {
  late GamepadNavigation _gamepadNav;
  final ScrollController _scrollController = ScrollController();
  int _selectedIndex = 0;
  int _crossAxisCount = 5;
  bool _isNavigatingFast = false;
  DateTime? _lastNavTime;
  static const Duration _fastNavThreshold = Duration(milliseconds: 150);

  // Debounced "settled" selection driving the footer + legend, so that chrome
  // isn't rebuilt on every gamepad move during a fast-navigation burst. The
  // in-cell selection border still tracks _selectedIndex every move.
  int _settledIndex = 0;
  Timer? _settleTimer;
  static const Duration _chromeSettleDelay = Duration(milliseconds: 160);
  String? _chromeSig;

  /// Whether a bulk sync is running, mirrored from
  /// [RommProvider.bulkSync] so the Y affordance reads "Cancel sync".
  bool _syncing = false;
  Widget? _chromeFooter;

  // Memoized grid rows. Cards are a pure function of the layout generation, the
  // decode width and the theme, so a settle / legend / download-progress
  // setState returns identical Row instances and Flutter skips those subtrees.
  int _layoutGen = 0;
  final Map<int, Widget> _rowCache = {};
  String? _rowCacheSig;
  String _lastDownloadsSig = '';

  // True while a deferred page request is already queued for after this frame.
  bool _pageRequestScheduled = false;

  // Layout model.
  List<_CardRect> _cardRects = [];
  List<_RowInfo> _rows = [];
  double _cardWidth = 0;
  double _spX = 0;
  double _spY = 0;
  double? _lastLayoutWidth;
  int? _lastLayoutCols;
  double _contentHeight = 0;
  bool _recenterAfterLayout = false;

  /// Per-card height/width ratio, independent of the card width, so a reflow
  /// (legend toggle, size cycle) is cheap arithmetic rather than a re-measure.
  List<double> _cardHOverW = [];
  bool _needsMeasure = true;

  // Cover measurement. Ratios arrive asynchronously as artwork decodes; they
  // are coalesced into one relayout rather than one per image, and only cards
  // that actually got built are ever measured (so nothing is prefetched).
  final Set<int> _measureRequested = {};
  Timer? _measureSettle;
  static const Duration _measureSettleDelay = Duration(milliseconds: 400);

  // Pinch-to-resize tracking.
  final Map<int, Offset> _activePointers = {};
  double? _lastPinchDistance;
  DateTime? _lastPinchTime;

  // Transient centre label shown while cycling the card size.
  final ValueNotifier<String?> _cardSizeLabel = ValueNotifier(null);
  Timer? _cardSizeLabelTimer;

  static const String _navLayerId = 'romm_rom_grid';

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(
      0,
      (widget.roms.length - 1).clamp(0, 999999),
    );
    _settledIndex = _selectedIndex;
    _updateCrossAxisCount();
    _initializeGamepad();
    _syncing = widget.provider.bulkSync.isRunning;
    widget.provider.bulkSync.addListener(_onBulkSyncChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        _navLayerId,
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
      _ensureSelectedVisible();
    });
  }

  @override
  void dispose() {
    _cardSizeLabelTimer?.cancel();
    _settleTimer?.cancel();
    _measureSettle?.cancel();
    _cardSizeLabel.dispose();
    widget.provider.bulkSync.removeListener(_onBulkSyncChanged);
    GamepadNavigationManager.popLayer(_navLayerId);
    _gamepadNav.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Theme / MediaQuery / ScreenUtil may have changed; drop the memoized
    // chrome so it rebuilds with fresh sizing on the next build.
    _chromeSig = null;
    _updateCrossAxisCount();
  }

  @override
  void didUpdateWidget(RommRomGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    final prevCols = _crossAxisCount;
    _updateCrossAxisCount();
    if (_crossAxisCount != prevCols) {
      // Card size cycled via the dropdown — recentre on the selected card once
      // the new layout is painted so the view follows the cursor.
      _recenterAfterLayout = true;
    }
    // Length, not identity: RommProvider.roms hands out a fresh unmodifiable
    // copy on every read, so an identity check would report "changed" on every
    // notification (download ticks included) and throw the layout and row
    // caches away dozens of times a second. Paging only ever appends, and a
    // change of platform/collection remounts this widget via its key.
    final romsChanged = widget.roms.length != oldWidget.roms.length;
    if (romsChanged || _crossAxisCount != prevCols) {
      _lastLayoutWidth = null;
      if (romsChanged) _needsMeasure = true;
      _rowCache.clear();
    }
    // Cached rows hold the download overlay, so a transfer starting, ticking or
    // finishing has to invalidate them — but nothing else about a provider
    // notification should.
    final downloadsSig = _downloadsSig();
    if (downloadsSig != _lastDownloadsSig) {
      _lastDownloadsSig = downloadsSig;
      _rowCache.clear();
    }
    if (_selectedIndex >= widget.roms.length) {
      _selectedIndex = (widget.roms.length - 1).clamp(0, 999999);
      _settledIndex = _selectedIndex;
    }
  }

  /// Cheap fingerprint of the download state the memoized rows draw.
  ///
  /// Bounded by what is in flight — at most one per sync worker — plus the
  /// provider's revision, which covers a download that starts *and* finishes
  /// between two builds and so is never seen in the active set.
  ///
  /// It used to fingerprint the whole download map, which accumulates every
  /// ROM fetched since connecting: by the end of a 636-ROM platform sync that
  /// was a 636-entry list, a sort and a multi-KB string built on every frame.
  /// It also carried the raw `fraction`, which moves with every network chunk,
  /// so the row cache was thrown away every frame by the very traffic it
  /// exists to survive. The cards only ever draw the rounded percentage.
  String _downloadsSig() {
    final provider = widget.provider;
    final active = provider.activeDownloadIds.toList()..sort();
    final sig = StringBuffer()..write(provider.downloadsRevision);
    for (final id in active) {
      final fraction = provider.downloadFor(id)?.fraction;
      sig.write(';$id:${fraction == null ? -1 : (fraction * 100).round()}');
    }
    return sig.toString();
  }

  void _initializeGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: () => _navDelta(-_cols),
      onNavigateDown: () => _navDelta(_cols),
      onNavigateLeft: () => _navHoriz(-1),
      onNavigateRight: () => _navHoriz(1),
      onSelectItem: _confirmSelected,
      onBack: widget.onBack,
      onXButton: widget.onToggleView,
      onFavorite: widget.onSyncAll, // Y — sync the whole source.
      onPreviousTab: AppNavigation.previousTab,
      onNextTab: AppNavigation.nextTab,
      onLeftBumper: AppNavigation.previousTab,
      onRightBumper: AppNavigation.nextTab,
    );
  }

  RommRom? get _focusedRom => widget.roms.isEmpty
      ? null
      : widget.roms[_settledIndex.clamp(0, widget.roms.length - 1)];

  void _confirmSelected() {
    if (widget.roms.isEmpty) return;
    widget.onConfirm(
      widget.roms[_selectedIndex.clamp(0, widget.roms.length - 1)],
    );
  }

  // ---- Card size ----

  void _updateCrossAxisCount() {
    try {
      switch (context.read<SqliteConfigProvider>().config.gameGridColumns) {
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

  int get _cols => _crossAxisCount.clamp(1, 10);

  void _adjustGridDensity(int delta) {
    try {
      final provider = context.read<SqliteConfigProvider>();
      const sizes = ['S', 'M', 'L', 'XL'];
      final currentIndex = sizes.indexOf(provider.config.gameGridColumns);
      if (currentIndex == -1) return;
      final newIndex = (currentIndex + delta).clamp(0, sizes.length - 1);
      if (newIndex == currentIndex) return;
      final newSize = sizes[newIndex];
      // Pinch changes cols locally, so didUpdateWidget won't see the delta —
      // request the recentre here instead.
      _recenterAfterLayout = true;
      provider.updateGameGridColumns(newSize);
      _updateCrossAxisCount();
      _lastLayoutWidth = null;
      _showCardSizeLabel(newSize);
      setState(() {});
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
    if (_lastPinchDistance == null) {
      _lastPinchDistance = distance;
      return;
    }
    final deltaDistance = distance - _lastPinchDistance!;
    if (deltaDistance.abs() <= 35) return;
    _adjustGridDensity(deltaDistance > 0 ? 1 : -1);
    _lastPinchDistance = distance;
    _lastPinchTime = now;
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) _lastPinchDistance = null;
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);
    if (_activePointers.length < 2) _lastPinchDistance = null;
  }

  // ---- Measurement + layout ----

  String? _coverUrl(int index) =>
      widget.provider.service.coverUrl(widget.roms[index]);

  double _heightRatioFor(int index) =>
      RommCoverAspect.ratioOf(_coverUrl(index)) ?? RommCoverAspect.fallback;

  void _measureCards() {
    final n = widget.roms.length;
    _cardHOverW = List<double>.filled(n, RommCoverAspect.fallback);
    for (int i = 0; i < n; i++) {
      _cardHOverW[i] = _heightRatioFor(i);
    }
    _needsMeasure = false;
  }

  /// Requests the real aspect for a card the moment it is first built. Anything
  /// that never scrolls into view is never measured, so a 5,000-ROM platform
  /// doesn't fetch 5,000 covers to lay itself out.
  void _ensureMeasured(int index) {
    if (_measureRequested.contains(index)) return;
    final url = _coverUrl(index);
    if (url == null) return;
    _measureRequested.add(index);
    if (RommCoverAspect.isMeasured(url)) return;
    RommCoverAspect.measure(
      url,
      NetworkImage(url, headers: widget.provider.service.imageHeadersFor(url)),
      _scheduleReflow,
    );
  }

  /// Coalesces incoming cover measurements into a single relayout. Only covers
  /// whose real aspect differs from the assumed one get this far (see
  /// [RommCoverAspect.measure]), which for a typical IGDB-sourced library is
  /// almost none — so in practice the grid settles on its first layout.
  void _scheduleReflow() {
    if (!mounted) return;
    _measureSettle?.cancel();
    _measureSettle = Timer(_measureSettleDelay, () {
      if (!mounted) return;
      setState(() {
        _needsMeasure = true;
        _lastLayoutWidth = null;
      });
    });
  }

  void _computeLayout(double availableWidth) {
    final measureChanged =
        _needsMeasure || _cardHOverW.length != widget.roms.length;

    if (!measureChanged &&
        _lastLayoutWidth == availableWidth &&
        _lastLayoutCols == _cols) {
      return;
    }

    if (measureChanged) _measureCards();

    _lastLayoutWidth = availableWidth;
    _lastLayoutCols = _cols;
    _positionCards(availableWidth);
  }

  /// Cheap positioning pass: cached aspect ratios + a target width become card
  /// rects and row bounds. No image work, and rects are mutated in place so a
  /// reflow animation allocates nothing.
  void _positionCards(double availableWidth) {
    final spX = 6.0.r;
    final spY = 6.0.r;
    _spX = spX;
    _spY = spY;

    final totalWidth = availableWidth - 32;
    _cardWidth = (totalWidth - (_cols - 1) * spX) / _cols;
    final n = widget.roms.length;
    final rowCount = _cols > 0 ? (n + _cols - 1) ~/ _cols : 0;

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
    _contentHeight = y;
    _layoutGen++;
  }

  // ---- Navigation ----

  void _updateFastNav() {
    final now = DateTime.now();
    _isNavigatingFast =
        _lastNavTime != null &&
        now.difference(_lastNavTime!) < _fastNavThreshold;
    _lastNavTime = now;
  }

  void _navDelta(int delta) {
    if (widget.roms.isEmpty) return;
    final c = _cols;
    final n = widget.roms.length;

    // Moving down off the last loaded row with more pages to come: page in and
    // HOLD the cursor. Wrapping to the top here is what made the cursor "snap
    // back" when navigating faster than pages load.
    if (delta > 0 &&
        _selectedIndex + delta >= n &&
        widget.provider.romsHasMore) {
      if (!widget.provider.loadingRoms) widget.provider.loadMoreRoms();
      return;
    }

    setState(() {
      int ni = _selectedIndex + delta;
      if (delta < 0 && ni < 0) {
        final col = _selectedIndex % c;
        ni = ((n / c).ceil() - 1) * c + col;
        while (ni >= n) {
          ni -= c;
        }
        if (ni < 0) ni = _selectedIndex;
      } else if (delta > 0 && ni >= n) {
        ni = _selectedIndex % c;
      }
      _selectedIndex = ni.clamp(0, n - 1);
      _updateFastNav();
    });
    _ensureSelectedVisible();
    _onSelectionChanged();
    SfxService().playNavSound();
  }

  void _navHoriz(int dir) {
    if (widget.roms.isEmpty) return;
    final n = widget.roms.length;
    setState(() {
      int ni;
      if (dir < 0) {
        final wrapRight = (_selectedIndex ~/ _cols) * _cols + _cols - 1;
        ni = _selectedIndex % _cols == 0
            ? (wrapRight < n - 1 ? wrapRight : n - 1)
            : _selectedIndex - 1;
      } else {
        final next = _selectedIndex + 1;
        ni = (next % _cols == 0 || next >= n)
            ? (_selectedIndex ~/ _cols) * _cols
            : next;
      }
      _selectedIndex = ni.clamp(0, n - 1);
      _updateFastNav();
    });
    _ensureSelectedVisible();
    _onSelectionChanged();
    SfxService().playNavSound();
  }

  void _onSelectionChanged() {
    widget.onIndexChanged(_selectedIndex);
    _scheduleChromeSettle();
    _maybeLoadMore();
  }

  /// Pages in more ROMs when the selection nears the end of the loaded set.
  void _maybeLoadMore() {
    final n = widget.roms.length;
    if (widget.provider.romsHasMore &&
        !widget.provider.loadingRoms &&
        _selectedIndex >= n - _cols * 2) {
      _requestPage();
    }
  }

  /// Asks for the next page *after* the current frame.
  ///
  /// [loadMoreRoms] flips its loading flag and calls `notifyListeners()`
  /// synchronously, and the host screen watches this provider — so calling it
  /// straight from a scroll notification marks elements dirty in the middle of
  /// layout. Deferring keeps the paging request out of the layout pass.
  void _requestPage() {
    if (_pageRequestScheduled) return;
    _pageRequestScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pageRequestScheduled = false;
      if (!mounted) return;
      if (widget.provider.romsHasMore && !widget.provider.loadingRoms) {
        widget.provider.loadMoreRoms();
      }
    });
  }

  /// Advances the footer/legend's settled selection. A single (slow) move
  /// updates it immediately; during a fast-nav burst it is deferred until
  /// navigation settles so the chrome isn't rebuilt every frame.
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

  /// Scroll offset that centres the selected card, clamped against the EXACT
  /// content height rather than the sliver's lazy estimate — which under-reports
  /// right after a relayout and would otherwise clamp a far jump short, leaving
  /// the selection off-screen.
  double _centerTargetFor(_CardRect rect, double viewportH) {
    final maxScroll = (12 + _contentHeight + 80 - viewportH).clamp(
      0.0,
      double.infinity,
    );
    return (12 + rect.top + rect.height / 2 - viewportH / 2).clamp(
      0.0,
      maxScroll,
    );
  }

  void _ensureSelectedVisible() {
    if (!_scrollController.hasClients || _cardRects.isEmpty) return;
    final rect = _cardRects[_selectedIndex.clamp(0, _cardRects.length - 1)];
    final pos = _scrollController.position;
    final target = _centerTargetFor(rect, pos.viewportDimension);
    // During a fast-nav burst, jump instantly rather than firing a fresh
    // animateTo per keypress — overlapping animations let the viewport trail
    // the selection by many rows.
    if (_isNavigatingFast) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutQuart,
    );
  }

  void _centerOnSelected() {
    if (!_scrollController.hasClients || _cardRects.isEmpty) return;
    final rect = _cardRects[_selectedIndex.clamp(0, _cardRects.length - 1)];
    final pos = _scrollController.position;
    final target = _centerTargetFor(rect, pos.viewportDimension);
    if ((pos.pixels - target).abs() <= 1.0) return;
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    _buildSettledChrome();

    return Column(
      children: [
        Expanded(
          child: widget.roms.isEmpty
              ? const SizedBox.shrink()
              : LayoutBuilder(
                  builder: (context, constraints) {
                    _computeLayout(constraints.maxWidth);
                    if (_recenterAfterLayout) {
                      _recenterAfterLayout = false;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _centerOnSelected();
                      });
                    }
                    return _buildScrollView(context);
                  },
                ),
        ),
        _chromeFooter!,
      ],
    );
  }

  Widget _buildScrollView(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.colorScheme.secondary;

    // Quantize the decode resolution into buckets so the small per-frame width
    // changes during a reflow don't thrash every card into re-decoding.
    const decodeBucket = 64;
    final bucketed = ((_cardWidth * 1.5) / decodeBucket).ceil() * decodeBucket;
    final targetWidth = bucketed < decodeBucket ? decodeBucket : bucketed;

    final rowSig = '$_layoutGen|$targetWidth|${theme.brightness.index}';
    if (rowSig != _rowCacheSig) {
      _rowCacheSig = rowSig;
      _rowCache.clear();
    }

    Widget buildRow(BuildContext ctx, int rowIndex) {
      final row = _rows[rowIndex];
      // The selection cursor is drawn INSIDE the selected card's cell, so it is
      // part of the card's own coordinate space — pixel-exact through scroll,
      // resize, mode switch and legend toggle, with no offset math. That one
      // row can't be memoized (its border must appear/vanish with the
      // selection); every other row stays cached.
      final hasSelection =
          _selectedIndex >= row.startIndex &&
          _selectedIndex < row.startIndex + row.count;
      if (!hasSelection) {
        final cached = _rowCache[rowIndex];
        if (cached != null) return cached;
      }

      final cards = <Widget>[];
      for (int j = 0; j < row.count; j++) {
        final idx = row.startIndex + j;
        if (idx >= widget.roms.length) break;
        final rect = _cardRects[idx];
        _ensureMeasured(idx);
        Widget cell = _buildCard(idx);
        if (idx == _selectedIndex) {
          cell = Stack(
            children: [
              cell,
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: borderColor, width: 4.r),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
        cards.add(
          SizedBox(width: rect.width, height: rect.height, child: cell),
        );
      }

      final built = SizedBox(
        height: row.height + _spY,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: _interleaveSpacing(cards, _spX),
        ),
      );
      if (!hasSelection) _rowCache[rowIndex] = built;
      return built;
    }

    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [
          NotificationListener<ScrollNotification>(
            onNotification: (scroll) {
              if (scroll.metrics.pixels >=
                      scroll.metrics.maxScrollExtent - 200.r &&
                  widget.provider.romsHasMore &&
                  !widget.provider.loadingRoms) {
                _requestPage();
              }
              return false;
            },
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.only(
                    top: 12,
                    bottom: 80,
                    left: 16,
                    right: 16,
                  ),
                  // Exact per-row extents let the sliver compute absolute
                  // offsets for the WHOLE list without building rows, so
                  // model-based centring always lands while rows stay lazy.
                  sliver: SliverVariedExtentList.builder(
                    itemCount: _rows.length,
                    itemExtentBuilder: (index, _) {
                      if (index < 0 || index >= _rows.length) return 0;
                      return _rows[index].height + _spY;
                    },
                    itemBuilder: buildRow,
                  ),
                ),
              ],
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
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.9,
                            ),
                            borderRadius: BorderRadius.circular(24.r),
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
  }

  Widget _buildCard(int index) {
    final rom = widget.roms[index];
    return RommRomCard(
      key: ValueKey('romm_rom_${rom.id}'),
      rom: rom,
      provider: widget.provider,
      romFolders: widget.romFolders,
      isFocused: false, // The in-cell cursor above draws the selection.
      onDownload: () => widget.onConfirm(rom),
      onCancel: () => widget.onCancel(rom),
      onTap: () {
        // Second tap on the already-selected tile confirms it — download, or
        // cancel one in flight. Touch users have no A button, and the local
        // library's grid reads the same way.
        if (index == _selectedIndex) {
          SfxService().playEnterSound();
          widget.onConfirm(rom);
          return;
        }
        setState(() {
          _selectedIndex = index;
          _settledIndex = index; // discrete tap: update chrome immediately
        });
        _settleTimer?.cancel();
        widget.onIndexChanged(index);
        SfxService().playNavSound();
      },
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

  /// (Re)builds the footer + legend only when the settled selection or its
  /// download state changes, so a fast-nav burst reuses the same instances.
  /// Repaints the chrome only when a bulk sync starts or stops.
  ///
  /// The sync notifies on every queue step; the only thing this view shows is
  /// whether one is running, so anything finer is a rebuild for nothing (the
  /// progress itself lives in the banner, which listens separately).
  void _onBulkSyncChanged() {
    if (!mounted) return;
    final running = widget.provider.bulkSync.isRunning;
    if (running == _syncing) return;
    setState(() => _syncing = running);
  }

  void _buildSettledChrome() {
    final rom = _focusedRom;
    final download = rom == null ? null : widget.provider.downloadFor(rom.id);
    // The completed-download entry only knows about this visit, and is dropped
    // when the screen remounts; the tile's own disk probe is what still knows
    // afterwards. In the sig so the icon settles once that probe lands.
    final onDisk = rom != null && widget.provider.downloadedStateFor(rom.id);
    final sig =
        '$_settledIndex|${rom?.id}|${download?.status}|${download?.fraction}|$onDisk|$_syncing';
    if (sig == _chromeSig && _chromeFooter != null) {
      return;
    }
    _chromeSig = sig;
    _chromeFooter = widget.footerBuilder(rom);
  }
}

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
