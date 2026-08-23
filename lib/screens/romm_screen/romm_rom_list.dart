import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../models/romm_rom.dart';
import '../../providers/romm_provider.dart';
import '../../services/game_legend_visibility.dart';
import '../../services/gamepad/gamepad_navigation_manager.dart';
import '../../services/sfx_service.dart';
import '../../utils/gamepad_nav.dart';
import '../../utils/letter_jump.dart';
import '../../widgets/legend_edge_reshow_zone.dart';
import '../../widgets/romm_action_buttons.dart';
import '../app_screen.dart';
import 'romm_rom_card.dart';

/// Detail-rich list view for the RomM browser's ROM view.
///
/// Full-width rows (thumbnail, name, metadata, download control) in a single
/// column, so up/down step one row and the scroll arithmetic is trivial. Wears
/// the same vertical legend and settled-selection footer as the grid,
/// matching the local library's list view.
class RommRomList extends StatefulWidget {
  final RommProvider provider;
  final List<RommRom> roms;
  final List<String> romFolders;

  /// Index to open on, so the selection survives a view-mode switch.
  final int initialIndex;
  final ValueChanged<int> onIndexChanged;

  /// A / the on-row control — start (or cancel) the ROM's download.
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

  const RommRomList({
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
  State<RommRomList> createState() => _RommRomListState();
}

class _RommRomListState extends State<RommRomList> {
  late GamepadNavigation _gamepadNav;
  final ScrollController _scrollController = ScrollController();
  int _selectedIndex = 0;

  // Debounced "settled" selection driving the footer + legend.
  int _settledIndex = 0;
  Timer? _settleTimer;
  DateTime? _lastNavTime;
  bool _isNavigatingFast = false;
  static const Duration _fastNavThreshold = Duration(milliseconds: 150);
  static const Duration _chromeSettleDelay = Duration(milliseconds: 160);
  String? _chromeSig;

  /// Whether a bulk sync is running, mirrored from
  /// [RommProvider.bulkSync] so the Y affordance reads "Cancel sync".
  bool _syncing = false;
  Widget? _chromeFooter;
  Widget? _chromeLegend;

  // True while a deferred page request is already queued for after this frame.
  bool _pageRequestScheduled = false;

  static const String _navLayerId = 'romm_rom_list';

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex.clamp(
      0,
      (widget.roms.length - 1).clamp(0, 999999),
    );
    _settledIndex = _selectedIndex;
    _initializeGamepad();
    GameLegendVisibility.hidden.addListener(_onLegendVisibilityChanged);
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
      _scrollToSelected(animate: false);
    });
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    GameLegendVisibility.hidden.removeListener(_onLegendVisibilityChanged);
    widget.provider.bulkSync.removeListener(_onBulkSyncChanged);
    GamepadNavigationManager.popLayer(_navLayerId);
    _gamepadNav.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chromeSig = null;
  }

  @override
  void didUpdateWidget(RommRomList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Length, not identity — RommProvider.roms returns a fresh copy per read.
    if (widget.roms.length != oldWidget.roms.length &&
        _selectedIndex >= widget.roms.length) {
      _selectedIndex = (widget.roms.length - 1).clamp(0, 999999);
      _settledIndex = _selectedIndex;
    }
  }

  void _initializeGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: () => _move(-1),
      onNavigateDown: () => _move(1),
      onLetterJump: _letterJump, // Held D-pad up/down → alphabet skipping.
      onSelectItem: _confirmSelected,
      onBack: widget.onBack,
      onXButton: widget.onToggleView,
      onFavorite: widget.onSyncAll, // Y — sync the whole source.
      onSelectModifierB: _toggleLegend, // Select + B - Hide/show legend.
      onPreviousTab: AppNavigation.previousTab,
      onNextTab: AppNavigation.nextTab,
      onLeftBumper: AppNavigation.previousTab,
      onRightBumper: AppNavigation.nextTab,
    );
  }

  void _toggleLegend() {
    SfxService().playNavSound();
    GameLegendVisibility.toggle();
  }

  void _onLegendVisibilityChanged() {
    if (mounted) setState(() {});
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

  /// Row height + separator, which is all the geometry a single-column list
  /// needs to centre a row that hasn't been built yet.
  double get _rowHeight => 98.r;
  double get _rowStride => _rowHeight + 8.r;

  void _move(int delta) {
    if (widget.roms.isEmpty) return;
    final n = widget.roms.length;

    // Stepping off the end with more pages to come: page in and HOLD the
    // cursor rather than wrapping to the top past unloaded rows.
    if (delta > 0 &&
        _selectedIndex + delta >= n &&
        widget.provider.romsHasMore) {
      if (!widget.provider.loadingRoms) widget.provider.loadMoreRoms();
      return;
    }

    final now = DateTime.now();
    _isNavigatingFast =
        _lastNavTime != null &&
        now.difference(_lastNavTime!) < _fastNavThreshold;
    _lastNavTime = now;

    setState(() {
      final next = _selectedIndex + delta;
      _selectedIndex = next < 0 ? n - 1 : (next >= n ? 0 : next);
    });
    _scrollToSelected();
    widget.onIndexChanged(_selectedIndex);
    _scheduleChromeSettle();
    _maybeLoadMore();
    SfxService().playNavSound();
  }

  /// Skips to the neighbouring alphabetical group once up/down has been held
  /// long enough (ES-DE style), the same escalation the local games list wears.
  ///
  /// Returns false at the ends of the alphabet so [GamepadNavigation] falls
  /// back to a normal step — which on a partially loaded platform is also what
  /// pages the next batch in, so a held jump forward keeps going once the rows
  /// arrive.
  bool _letterJump(bool forward) {
    if (widget.roms.isEmpty) return false;

    final target = LetterJump.targetIndex(
      length: widget.roms.length,
      currentIndex: _selectedIndex,
      forward: forward,
      letterAt: (index) => LetterJump.letterForName(widget.roms[index].name),
    );
    if (target == null) return false;

    // A jump is a large move by definition, so scroll without animating: a run
    // of held jumps would otherwise stack animations and trail the cursor.
    _isNavigatingFast = true;
    _lastNavTime = DateTime.now();
    setState(() => _selectedIndex = target);
    _scrollToSelected(animate: false);
    widget.onIndexChanged(_selectedIndex);
    _scheduleChromeSettle();
    _maybeLoadMore();
    SfxService().playNavSound();
    return true;
  }

  void _maybeLoadMore() {
    if (widget.provider.romsHasMore &&
        !widget.provider.loadingRoms &&
        _selectedIndex >= widget.roms.length - 4) {
      _requestPage();
    }
  }

  /// Asks for the next page *after* the current frame. loadMoreRoms() notifies
  /// synchronously and the host screen watches this provider, so calling it
  /// straight from a scroll notification would dirty elements mid-layout.
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

  void _scrollToSelected({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final target =
          12.r +
          _selectedIndex * _rowStride -
          (pos.viewportDimension - _rowHeight) / 2;
      final clamped = target.clamp(pos.minScrollExtent, pos.maxScrollExtent);
      // A fast-nav burst jumps instead of stacking up overlapping animations,
      // which would let the viewport trail the cursor by many rows.
      if (!animate || _isNavigatingFast) {
        pos.jumpTo(clamped);
        return;
      }
      pos.animateTo(
        clamped,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    _buildSettledChrome();

    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              // Indent to clear the vertical legend, exactly as the local game
              // list does; the rows reflow in a single frame on Select + B.
              child: Padding(
                padding: EdgeInsets.only(
                  left: GameLegendVisibility.hidden.value ? 0 : 48.r,
                ),
                child: widget.roms.isEmpty
                    ? const SizedBox.shrink()
                    : NotificationListener<ScrollNotification>(
                        onNotification: (scroll) {
                          if (scroll.metrics.pixels >=
                                  scroll.metrics.maxScrollExtent - 200.r &&
                              widget.provider.romsHasMore &&
                              !widget.provider.loadingRoms) {
                            _requestPage();
                          }
                          return false;
                        },
                        child: ListView.separated(
                          controller: _scrollController,
                          padding: EdgeInsets.fromLTRB(12.r, 12.r, 12.r, 12.r),
                          itemCount: widget.roms.length,
                          separatorBuilder: (_, _) => SizedBox(height: 8.r),
                          itemBuilder: (context, index) {
                            final rom = widget.roms[index];
                            return SizedBox(
                              height: _rowHeight,
                              child: RommRomCard(
                                key: ValueKey('romm_row_${rom.id}'),
                                rom: rom,
                                provider: widget.provider,
                                romFolders: widget.romFolders,
                                isFocused: _selectedIndex == index,
                                layout: RommRomLayout.list,
                                onDownload: () => widget.onConfirm(rom),
                                onCancel: () => widget.onCancel(rom),
                                onTap: () {
                                  // Second tap on the selected row confirms
                                  // it (see RommRomGrid._buildCard).
                                  if (index == _selectedIndex) {
                                    SfxService().playEnterSound();
                                    widget.onConfirm(rom);
                                    return;
                                  }
                                  setState(() {
                                    _selectedIndex = index;
                                    _settledIndex = index;
                                  });
                                  _settleTimer?.cancel();
                                  widget.onIndexChanged(index);
                                  SfxService().playNavSound();
                                },
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ),
            _chromeFooter!,
          ],
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutCubic,
          top: 12.r,
          left: GameLegendVisibility.hidden.value ? -60.r : 10.r,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 250),
            opacity: GameLegendVisibility.hidden.value ? 0.0 : 1.0,
            child: _chromeLegend!,
          ),
        ),
        // Touch: swipe-right from the left edge reveals a hidden legend.
        const LegendEdgeReshowZone(),
      ],
    );
  }

  /// (Re)builds the footer + legend only when the settled selection or its
  /// download state changes.
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
    // See RommRomGrid._buildSettledChrome: the completed-download entry is
    // visit-scoped, the tile's disk probe is what outlives it.
    final onDisk = rom != null && widget.provider.downloadedStateFor(rom.id);
    final sig =
        '$_settledIndex|${rom?.id}|${download?.status}|${download?.fraction}|$onDisk|$_syncing';
    if (sig == _chromeSig && _chromeFooter != null && _chromeLegend != null) {
      return;
    }
    _chromeSig = sig;
    _chromeFooter = widget.footerBuilder(rom);
    _chromeLegend = RommActionButtons(
      onBack: widget.onBack,
      onViewMode: widget.onToggleView,
      onDownload: rom == null
          ? null
          : () => download?.status == RommDownloadStatus.downloading
                ? widget.onCancel(rom)
                : widget.onConfirm(rom),
      isDownloading: download?.status == RommDownloadStatus.downloading,
      isDownloaded: download?.status == RommDownloadStatus.completed || onDisk,
      onSyncAll: widget.onSyncAll,
      isSyncing: _syncing,
    );
  }
}
