import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/database_game_model.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/secondary_display_state.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/repositories/game_repository.dart';
import 'package:neostation/screens/search_screen/search_filter.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/sync/sync_manager.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/services/secondary_achievements_controller.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/utils/game_launch_utils.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/screens/game_screen/my_games_list.dart';
import 'package:neostation/screens/app_screen.dart';

/// Library-wide ROM search & filter overlay.
///
/// Loads every game across all systems once, then filters in-memory by name
/// plus platform / developer / genre / rating / year. The filter options are
/// faceted — each chip only offers values still present in the results the
/// other criteria produce, so a filter never leads to an empty list.
///
/// Reachable as its own top-level tab; selecting a result offers Go-to-game or
/// launching it through the standard [launchGameWithDialog] flow.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

/// Which band currently owns gamepad focus.
///
/// The screen stacks top-to-bottom: [search] field, then the [filters] chip
/// row, then the full-width [results] list — Up/Down step between them.
/// [filterMenu] is the value picker opened from a chip; [action] is the
/// per-result chooser overlay (Go to game / Play) shown after a result is
/// selected, so launching is always an explicit step.
enum _FocusRegion { search, filters, results, filterMenu, action }

/// Ordered choices offered when a search result is selected.
enum _ResultAction { goTo, play }

class _SearchScreenState extends State<SearchScreen> {
  late GamepadNavigation _gamepadNav;

  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final ScrollController _resultScroll = ScrollController();

  bool _loading = true;
  List<DatabaseGameModel> _all = [];

  // Filter options for the current selection, recomputed on every change: each
  // dimension only offers values still reachable from the live results (empty
  // sets hide their chip). See [computeFacets].
  SearchFacets _facets = SearchFacets.empty;

  // Active filter values (null == Any).
  String? _platform;
  String? _developer;
  String? _genre;
  String? _year;
  int? _rating;

  _FocusRegion _region = _FocusRegion.search;
  int _barIndex = 0;
  int _resultIndex = 0;

  // Index into [_searchItems]: the text field, the clear-query X once there is
  // a query, then the Filters toggle. Filters stay collapsed by default — most
  // users only want text search.
  int _searchIndex = 0;
  bool _filtersExpanded = false;

  // Filter value-picker state, valid while _region == filterMenu. The original
  // value is snapshotted on open so Back can cancel a live preview.
  String? _menuKey;
  String? _menuOrigValue;
  int? _menuOrigRatingValue;
  final ScrollController _menuScroll = ScrollController();

  static const double _menuExtent = 44;

  // Active result-action chooser state (valid while _region == action).
  static const List<_ResultAction> _resultActions = [
    _ResultAction.goTo,
    _ResultAction.play,
  ];
  int _actionIndex = 0;
  DatabaseGameModel? _actionTarget;

  List<DatabaseGameModel> _results = [];

  // Resolved box-art path per ROM (null == no art); see [_resolveBoxArt].
  final Map<String, String?> _artCache = {};

  // The chip row scrolls horizontally rather than wrapping, so the focused chip
  // has to be scrolled into view; each chip carries a key to measure against.
  final ScrollController _chipScroll = ScrollController();
  final Map<int, GlobalKey> _chipKeys = {};

  // Secondary-display "Now Playing" / in-game achievements panel for games
  // launched straight from the results list. Android-only; null elsewhere.
  SecondaryDisplayState? _secondaryDisplayState;
  final SecondaryAchievementsController _achievementsController =
      SecondaryAchievementsController();

  static const double _resultExtent = 68;

  @override
  void initState() {
    super.initState();

    _gamepadNav = GamepadNavigation(
      onNavigateUp: _navigateUp,
      onNavigateDown: _navigateDown,
      onNavigateLeft: _navigateLeft,
      onNavigateRight: _navigateRight,
      onSelectItem: _handleSelect,
      onBack: _handleBack,
      // Search runs as a tab and owns the input layer while it is on screen,
      // so it has to keep the bumper/tab cycling working itself.
      onPreviousTab: AppNavigation.previousTab,
      onNextTab: AppNavigation.nextTab,
      onLeftBumper: AppNavigation.previousTab,
      onRightBumper: AppNavigation.nextTab,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'search_screen',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });

    if (Platform.isAndroid) {
      _secondaryDisplayState = SecondaryDisplayState.instance;
    }

    _loadGames();
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('search_screen');
    _achievementsController.dispose();
    _gamepadNav.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    _resultScroll.dispose();
    _menuScroll.dispose();
    _chipScroll.dispose();
    super.dispose();
  }

  Future<void> _loadGames() async {
    final games = await GameRepository.getAllGames();
    if (!mounted) return;

    setState(() {
      _all = games;
      _loading = false;
      _recompute();
    });
  }

  /// Extracts a 4-digit year from a raw year / ISO release-date string.
  String? _yearOf(DatabaseGameModel g) => searchYearOf(g);

  /// Recomputes the results *and* the filter options they support.
  ///
  /// Options are re-derived rather than taken once from the whole library, so
  /// a chip never offers a value that would return nothing. Chips can appear
  /// and disappear as a result, so the focused chip is tracked by key across
  /// the rebuild instead of by index.
  void _recompute() {
    final criteria = SearchCriteria(
      query: _nameController.text,
      platform: _platform,
      developer: _developer,
      genre: _genre,
      year: _year,
      rating: _rating,
    );

    _results = filterAndSortGames(_all, criteria);
    if (_resultIndex >= _results.length) {
      _resultIndex = _results.isEmpty ? 0 : _results.length - 1;
    }

    final focusedKey = _barIndex < _barItems.length
        ? _barItems[_barIndex]
        : null;
    _facets = computeFacets(_all, criteria);
    final items = _barItems;
    final moved = focusedKey == null ? -1 : items.indexOf(focusedKey);
    _barIndex = moved >= 0 ? moved : _barIndex.clamp(0, items.length - 1);

    // Emptying the query drops the clear button out of the search band.
    _searchIndex = _searchIndex.clamp(0, _lastSearchIndex);
  }

  // ── Band model ──────────────────────────────────────────────────────────
  // Three stacked bands: search field, the filter-chip row, then results.
  // Up/Down step between bands; within the chip row Left/Right move between
  // chips. Hidden (empty-option) filters are skipped entirely.

  /// Ordered keys of the currently visible filter chips.
  ///
  /// A chip is shown when the current results still offer a choice for it, or
  /// when it is the filter doing the narrowing — an active chip has to stay
  /// reachable so it can be cleared again.
  List<String> get _visibleFilters {
    bool shown(String key) =>
        _menuOptions(key).isNotEmpty || _isFilterActive(key);
    return [
      if (shown('platform')) 'platform',
      if (_facets.ratings.isNotEmpty || _rating != null) 'rating',
      if (shown('developer')) 'developer',
      if (shown('genre')) 'genre',
      if (shown('year')) 'year',
    ];
  }

  /// Chip-row items left-to-right: each visible filter, then Clear.
  List<String> get _barItems => [..._visibleFilters, 'clear'];

  /// Number of filters currently narrowing the results (shown on the toggle
  /// so applied filters stay visible even while the chip row is collapsed).
  int get _activeFilterCount =>
      [_platform, _developer, _genre, _year].where((v) => v != null).length +
      (_rating != null ? 1 : 0);

  /// Focusable items in the search band, left-to-right. The clear button only
  /// exists while there is a query to clear.
  List<String> get _searchItems => [
    'field',
    if (_nameController.text.isNotEmpty) 'clearQuery',
    'filters',
  ];

  int get _lastSearchIndex => _searchItems.length - 1;

  /// Key of the search-band item holding focus.
  String get _focusedSearchItem =>
      _searchItems[_searchIndex.clamp(0, _lastSearchIndex)];

  /// Whether the search band owns focus and it sits on [key].
  bool _searchFocused(String key) =>
      _region == _FocusRegion.search && _focusedSearchItem == key;

  /// Shows/hides the filter chip row, moving focus to follow.
  void _toggleFilters() {
    setState(() {
      _filtersExpanded = !_filtersExpanded;
      if (_filtersExpanded) {
        _region = _FocusRegion.filters;
        _barIndex = 0;
      } else {
        _region = _FocusRegion.search;
        _searchIndex = _searchItems.indexOf('filters');
      }
    });
    SfxService().playNavSound();
  }

  /// Empties the name query, leaving the filter chips as they are, and hands
  /// focus back to the field the user was typing in.
  void _clearQuery() {
    setState(() {
      _nameController.clear();
      _searchIndex = 0;
      _recompute();
    });
    SfxService().playNavSound();
  }

  // ── Navigation handlers ───────────────────────────────────────────────────

  void _navigateLeft() {
    if (_region == _FocusRegion.search) {
      setState(
        () => _searchIndex = (_searchIndex - 1).clamp(0, _lastSearchIndex),
      );
      SfxService().playNavSound();
    } else if (_region == _FocusRegion.filters) {
      setState(
        () => _barIndex = (_barIndex - 1 + _barItems.length) % _barItems.length,
      );
      _scrollChipIntoView();
      SfxService().playNavSound();
    }
  }

  void _navigateRight() {
    if (_region == _FocusRegion.search) {
      setState(
        () => _searchIndex = (_searchIndex + 1).clamp(0, _lastSearchIndex),
      );
      SfxService().playNavSound();
    } else if (_region == _FocusRegion.filters) {
      setState(() => _barIndex = (_barIndex + 1) % _barItems.length);
      _scrollChipIntoView();
      SfxService().playNavSound();
    }
  }

  void _navigateUp() {
    switch (_region) {
      case _FocusRegion.action:
        setState(
          () => _actionIndex =
              (_actionIndex - 1 + _resultActions.length) %
              _resultActions.length,
        );
      case _FocusRegion.filterMenu:
        _moveMenuSelection(-1);
      case _FocusRegion.results:
        if (_resultIndex == 0) {
          setState(
            () => _region = _filtersExpanded
                ? _FocusRegion.filters
                : _FocusRegion.search,
          );
        } else {
          setState(() => _resultIndex -= 1);
          _scrollResultIntoView();
        }
      case _FocusRegion.filters:
        setState(() => _region = _FocusRegion.search);
      case _FocusRegion.search:
        break; // already at the top
    }
    SfxService().playNavSound();
  }

  void _navigateDown() {
    switch (_region) {
      case _FocusRegion.action:
        setState(
          () => _actionIndex = (_actionIndex + 1) % _resultActions.length,
        );
      case _FocusRegion.filterMenu:
        _moveMenuSelection(1);
      case _FocusRegion.results:
        if (_results.isEmpty) return;
        setState(
          () => _resultIndex = (_resultIndex + 1).clamp(0, _results.length - 1),
        );
        _scrollResultIntoView();
      case _FocusRegion.search:
        if (_filtersExpanded) {
          setState(() {
            _nameFocus.unfocus();
            _region = _FocusRegion.filters;
          });
        } else {
          _enterResults();
        }
      case _FocusRegion.filters:
        // Flow from the chip row straight into the live results list.
        _enterResults();
    }
    SfxService().playNavSound();
  }

  /// Moves focus into the results list if it has any entries.
  void _enterResults() {
    if (_results.isEmpty) return;
    setState(() {
      _nameFocus.unfocus();
      _region = _FocusRegion.results;
      _resultIndex = _resultIndex.clamp(0, _results.length - 1);
    });
    _scrollResultIntoView();
  }

  void _handleSelect() {
    switch (_region) {
      case _FocusRegion.action:
        _runResultAction(_resultActions[_actionIndex]);
      case _FocusRegion.filterMenu:
        // Confirm the live-previewed value.
        setState(() {
          _menuKey = null;
          _region = _FocusRegion.filters;
        });
      case _FocusRegion.search:
        switch (_focusedSearchItem) {
          case 'clearQuery':
            _clearQuery();
          case 'filters':
            _toggleFilters();
          default:
            // Hand focus to the text field so the keyboard opens.
            _nameFocus.requestFocus();
        }
      case _FocusRegion.results:
        // Open the per-result chooser instead of launching outright, so the
        // user can reveal the game in its list rather than always playing it.
        if (_results.isNotEmpty) {
          setState(() {
            _actionTarget = _results[_resultIndex];
            _actionIndex = 0;
            _region = _FocusRegion.action;
          });
          SfxService().playNavSound();
        }
      case _FocusRegion.filters:
        final item = _barItems[_barIndex];
        if (item == 'clear') {
          _clearFilters();
        } else {
          _openFilterMenu(item);
        }
    }
  }

  void _runResultAction(_ResultAction action) {
    final target = _actionTarget;
    if (target == null) return;
    setState(() => _region = _FocusRegion.results);
    switch (action) {
      case _ResultAction.play:
        _launch(target);
      case _ResultAction.goTo:
        _goToGame(target);
    }
  }

  void _handleBack() {
    if (_nameFocus.hasFocus) {
      _nameFocus.unfocus();
      return;
    }
    switch (_region) {
      case _FocusRegion.action:
        setState(() => _region = _FocusRegion.results);
      case _FocusRegion.filterMenu:
        _cancelFilterMenu();
      case _FocusRegion.results:
        setState(() => _region = _FocusRegion.search);
      case _FocusRegion.filters:
        setState(() => _region = _FocusRegion.search);
      case _FocusRegion.search:
        // Top of the search tab: stay put. Like every other tab, B does not
        // leave the tab — only the bumpers/tab strip change tabs.
        break;
    }
  }

  // ── Filter value menu ──────────────────────────────────────────────────────

  void _openFilterMenu(String key) {
    setState(() {
      _menuKey = key;
      _menuOrigValue = _currentFilterValue(key);
      _menuOrigRatingValue = _rating;
      _region = _FocusRegion.filterMenu;
    });
    _scrollMenuIntoView();
    SfxService().playNavSound();
  }

  /// Back out of the menu, restoring the value as it was before opening.
  void _cancelFilterMenu() {
    final key = _menuKey;
    setState(() {
      if (key == 'rating') {
        _rating = _menuOrigRatingValue;
      } else if (key != null) {
        _setFilterValue(key, _menuOrigValue);
      }
      _recompute();
      _menuKey = null;
      _region = _FocusRegion.filters;
    });
  }

  /// Moves the menu cursor by [delta], previewing the result live.
  void _moveMenuSelection(int delta) {
    final key = _menuKey;
    if (key == null) return;
    setState(() {
      if (key == 'rating') {
        _rating = cycleFilterValue(_facets.ratings, _rating, delta);
      } else {
        _setFilterValue(
          key,
          cycleFilterValue(_menuOptions(key), _currentFilterValue(key), delta),
        );
      }
      _recompute();
    });
    _scrollMenuIntoView();
  }

  /// Commits the menu entry at [index] (mouse / tap path) and closes.
  void _applyMenuIndex(String key, int index) {
    setState(() {
      if (key == 'rating') {
        _rating = index == 0 ? null : _facets.ratings[index - 1];
      } else {
        _setFilterValue(key, index == 0 ? null : _menuOptions(key)[index - 1]);
      }
      _recompute();
      _menuKey = null;
      _region = _FocusRegion.filters;
    });
  }

  List<String> _menuOptions(String key) => _facets.optionsFor(key);

  String? _currentFilterValue(String key) => switch (key) {
    'platform' => _platform,
    'developer' => _developer,
    'genre' => _genre,
    'year' => _year,
    _ => null,
  };

  void _setFilterValue(String key, String? value) {
    switch (key) {
      case 'platform':
        _platform = value;
      case 'developer':
        _developer = value;
      case 'genre':
        _genre = value;
      case 'year':
        _year = value;
    }
  }

  /// Index of the selected entry within the open menu's option list
  /// (0 == the leading "Any" slot).
  int _menuSelectedIndex(String key) {
    if (key == 'rating') {
      final cur = _rating;
      if (cur == null) return 0;
      final i = _facets.ratings.indexOf(cur);
      return i < 0 ? 0 : i + 1;
    }
    final cur = _currentFilterValue(key);
    if (cur == null) return 0;
    final i = _menuOptions(key).indexOf(cur);
    return i < 0 ? 0 : i + 1;
  }

  /// Resets every filter chip. The name query is deliberately left alone — it
  /// is the search itself, not one of the filters this button owns.
  void _clearFilters() {
    setState(() {
      _platform = null;
      _developer = null;
      _genre = null;
      _year = null;
      _rating = null;
      _recompute();
    });
    SfxService().playNavSound();
  }

  void _scrollResultIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_resultScroll.hasClients) return;
      final pos = _resultScroll.position;
      final target =
          (_resultIndex * _resultExtent.r) -
          (pos.viewportDimension - _resultExtent.r) / 2;
      pos.animateTo(
        target.clamp(pos.minScrollExtent, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    });
  }

  /// Keeps the selected menu entry visible when the option list overflows.
  void _scrollMenuIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _menuKey;
      if (key == null || !_menuScroll.hasClients) return;
      final pos = _menuScroll.position;
      final target =
          (_menuSelectedIndex(key) * _menuExtent.r) -
          (pos.viewportDimension - _menuExtent.r) / 2;
      pos.animateTo(
        target.clamp(pos.minScrollExtent, pos.maxScrollExtent),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _launch(DatabaseGameModel dbGame) async {
    final folder = dbGame.systemFolderName;
    if (folder == null || folder.isEmpty) return;

    final fileProvider = context.read<FileProvider>();
    final syncProvider = context.read<SyncManager>().active;
    if (syncProvider == null) return;

    final system = await SqliteService.getSystemByFolderName(folder);
    if (!mounted) return;

    final game = GameModel.fromDatabaseModel(dbGame);

    _gamepadNav.deactivate();

    // Drive the secondary display's "Now Playing" page (and the live RA panel)
    // for this session, exactly as the games list and the Recent Games cards do
    // — without this push the bottom screen never activates for a search-result
    // launch. Fired without awaiting so it never blocks the emulator handoff;
    // it lands during launchGameWithDialog's foreground window.
    // ignore: unawaited_futures
    _achievementsController.pushForLaunch(
      state: _secondaryDisplayState,
      provider: context.read<RetroAchievementsProvider>(),
      game: game,
      systemFolderName: system.primaryFolderName,
      boxartPath: SecondaryAchievementsController.resolveBoxart(
        game,
        system.primaryFolderName,
        fileProvider,
      ),
    );

    await launchGameWithDialog(
      context: context,
      game: game,
      system: system,
      fileProvider: fileProvider,
      syncProvider: syncProvider,
      onGameClosed: () {
        // Stop the poll and hide the panel; search pushes no display state of
        // its own, so the secondary fades back to whatever art is underneath.
        _achievementsController.stop(hidePanel: true);
        GamepadNavigationManager.reactivate();
      },
      onLaunchFailed: (ctx, result) async {
        _achievementsController.stop(hidePanel: true);
        if (mounted) {
          AppNotification.showNotification(
            context,
            AppLocale.errorLaunchingGame
                .getString(context)
                .replaceFirst('{error}', ''),
            type: NotificationType.error,
          );
        }
        GamepadNavigationManager.reactivate();
      },
    );
  }

  /// Opens the result's system game list with that game pre-selected, so the
  /// user lands on it in the normal browsing view.
  ///
  /// Search is a tab rather than an overlay, so this pushes on top of the tab
  /// and backing out of the game list returns here with the query intact.
  Future<void> _goToGame(DatabaseGameModel dbGame) async {
    final folder = dbGame.systemFolderName;
    if (folder == null || folder.isEmpty) return;

    final fileProvider = context.read<FileProvider>();
    final system = await SqliteService.getSystemByFolderName(folder);
    if (!mounted) return;

    final game = GameModel.fromDatabaseModel(dbGame);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SystemGamesList(
          system: system,
          fileProvider: fileProvider,
          initialRomPath: game.romPath,
        ),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Tab content sits under the global header, so it carries no Scaffold or
    // AppBar of its own — the leading SizedBox clears the header the same way
    // the other tabs do (32.r tab strip + margin).
    return _loading
        ? const Center(child: CircularProgressIndicator())
        : Stack(
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.r),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(height: 64.r),
                    _buildSearchRow(theme),
                    if (_filtersExpanded) ...[
                      SizedBox(height: 6.r),
                      _buildFilterChips(theme),
                    ],
                    SizedBox(height: 8.r),
                    Expanded(child: _buildResults(theme)),
                  ],
                ),
              ),
              if (_region == _FocusRegion.filterMenu && _menuKey != null)
                _buildFilterMenu(theme, _menuKey!),
              if (_region == _FocusRegion.action && _actionTarget != null)
                _buildActionChooser(theme, _actionTarget!),
            ],
          );
  }

  /// Modal overlay offering Go-to-game / Play for a selected result.
  Widget _buildActionChooser(ThemeData theme, DatabaseGameModel target) {
    final scheme = theme.colorScheme;
    return Positioned.fill(
      child: GestureDetector(
        onTap: () => setState(() => _region = _FocusRegion.results),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.6),
          child: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                width: 320.r,
                padding: EdgeInsets.all(16.r),
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(16.r),
                  border: Border.all(
                    color: scheme.primary.withValues(alpha: 0.4),
                    width: 1.r,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      target.realName ?? target.filename,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.r,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 12.r),
                    for (var i = 0; i < _resultActions.length; i++)
                      _buildActionOption(theme, _resultActions[i], i),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionOption(ThemeData theme, _ResultAction action, int index) {
    final scheme = theme.colorScheme;
    final isFocused = _actionIndex == index;
    final (icon, label) = switch (action) {
      _ResultAction.goTo => (
        Symbols.my_location_rounded,
        AppLocale.searchGoToGame.getString(context),
      ),
      _ResultAction.play => (
        Symbols.play_arrow_rounded,
        AppLocale.play.getString(context),
      ),
    };
    return GestureDetector(
      onTap: () {
        setState(() => _actionIndex = index);
        _runResultAction(action);
      },
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 4.r),
        padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 12.r),
        decoration: BoxDecoration(
          color: isFocused
              ? scheme.primary.withValues(alpha: 0.18)
              : scheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isFocused ? scheme.primary : Colors.transparent,
            width: 2.r,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18.r,
              color: isFocused ? scheme.primary : scheme.onSurface,
            ),
            SizedBox(width: 8.r),
            Text(
              label,
              style: TextStyle(
                fontSize: 14.r,
                fontWeight: FontWeight.w700,
                color: isFocused ? scheme.primary : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The filter-chip row beneath the search box: one chip per visible filter,
  /// then Clear.
  ///
  /// Scrolls horizontally on one line instead of wrapping — wrapping cost a
  /// second full chip row of vertical space (and the results list with it) on
  /// every handheld we target, for a row that is already Left/Right navigable.
  Widget _buildFilterChips(ThemeData theme) {
    final inFilters = _region == _FocusRegion.filters;
    final items = _barItems;
    return SingleChildScrollView(
      controller: _chipScroll,
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            KeyedSubtree(
              key: _chipKeys.putIfAbsent(i, () => GlobalKey()),
              child: items[i] == 'clear'
                  ? _buildClearChip(theme, inFilters && _barIndex == i)
                  : _buildFilterChip(
                      theme,
                      items[i],
                      inFilters && _barIndex == i,
                    ),
            ),
        ],
      ),
    );
  }

  /// Keeps the focused filter chip visible in the horizontally scrolling row.
  void _scrollChipIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chipContext = _chipKeys[_barIndex]?.currentContext;
      if (chipContext == null) return;
      Scrollable.ensureVisible(
        chipContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    });
  }

  /// The top band: the search field, the result count, and the Filters
  /// (advanced) toggle.
  ///
  /// The count rides in this row rather than owning a line above the list —
  /// on a handheld that line was a whole result's worth of height.
  Widget _buildSearchRow(ThemeData theme) {
    return Row(
      children: [
        Expanded(child: _buildNameField(theme, _searchFocused('field'))),
        SizedBox(width: 10.r),
        Text(
          AppLocale.searchResultsCount
              .getString(context)
              .replaceFirst('{count}', '${_results.length}'),
          style: TextStyle(
            fontSize: 12.r,
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        SizedBox(width: 10.r),
        _buildAdvancedToggle(theme, _searchFocused('filters')),
      ],
    );
  }

  /// Toggle that reveals/collapses the filter chip row. Shows a count badge so
  /// applied filters remain visible while collapsed.
  Widget _buildAdvancedToggle(ThemeData theme, bool focused) {
    final scheme = theme.colorScheme;
    final count = _activeFilterCount;
    final accent = focused || count > 0;
    return GestureDetector(
      onTap: _toggleFilters,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 9.r),
        decoration: BoxDecoration(
          color: focused
              ? scheme.primary.withValues(alpha: 0.18)
              : (count > 0
                    ? scheme.primary.withValues(alpha: 0.10)
                    : scheme.surface.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: focused
                ? scheme.primary
                : (count > 0
                      ? scheme.primary.withValues(alpha: 0.5)
                      : Colors.transparent),
            width: 2.r,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.tune_rounded,
              size: 18.r,
              color: accent ? scheme.primary : scheme.onSurface,
            ),
            SizedBox(width: 6.r),
            Text(
              AppLocale.searchFilters.getString(context),
              style: TextStyle(
                fontSize: 13.r,
                fontWeight: FontWeight.w700,
                color: accent ? scheme.primary : scheme.onSurface,
              ),
            ),
            if (count > 0) ...[
              SizedBox(width: 6.r),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 6.r, vertical: 1.r),
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 11.r,
                    fontWeight: FontWeight.w800,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
            ],
            SizedBox(width: 4.r),
            Icon(
              _filtersExpanded
                  ? Symbols.expand_less_rounded
                  : Symbols.expand_more_rounded,
              size: 16.r,
              color: scheme.onSurface.withValues(alpha: focused ? 0.9 : 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameField(ThemeData theme, bool focused) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: focused ? theme.colorScheme.primary : Colors.transparent,
          width: 2.r,
        ),
      ),
      child: TextField(
        controller: _nameController,
        focusNode: _nameFocus,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(_recompute),
        onSubmitted: (_) => _nameFocus.unfocus(),
        decoration: InputDecoration(
          hintText: AppLocale.searchNameHint.getString(context),
          prefixIcon: const Icon(Symbols.search_rounded),
          suffixIcon: _nameController.text.isEmpty
              ? null
              : _buildClearQueryButton(theme, _searchFocused('clearQuery')),
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 12.r,
            vertical: 10.r,
          ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.5,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12.r),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  /// The X inside the search field that empties the query.
  ///
  /// It is a focus stop of its own in the search band rather than a tap-only
  /// affordance, so it is reachable with the D-pad like everything else — and
  /// it only exists while there is a query, so Left/Right skip it otherwise.
  Widget _buildClearQueryButton(ThemeData theme, bool focused) {
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: _clearQuery,
      child: Container(
        margin: EdgeInsets.symmetric(horizontal: 6.r, vertical: 4.r),
        padding: EdgeInsets.all(4.r),
        decoration: BoxDecoration(
          color: focused
              ? scheme.primary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: focused ? scheme.primary : Colors.transparent,
            width: 2.r,
          ),
        ),
        child: Icon(
          Symbols.close_rounded,
          size: 18.r,
          color: focused
              ? scheme.primary
              : scheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  /// A single filter chip showing "Label: value"; tapping opens its picker.
  Widget _buildFilterChip(ThemeData theme, String key, bool isFocused) {
    final scheme = theme.colorScheme;
    final label = _filterLabel(key);
    final value = _filterValueLabel(key);
    final active = _isFilterActive(key);

    return GestureDetector(
      onTap: () {
        setState(() {
          _region = _FocusRegion.filters;
          _barIndex = _barItems.indexOf(key);
        });
        _openFilterMenu(key);
      },
      child: Container(
        margin: EdgeInsets.only(right: 8.r),
        padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 8.r),
        decoration: BoxDecoration(
          color: isFocused
              ? scheme.primary.withValues(alpha: 0.18)
              : (active
                    ? scheme.primary.withValues(alpha: 0.10)
                    : scheme.surface.withValues(alpha: 0.5)),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isFocused
                ? scheme.primary
                : (active
                      ? scheme.primary.withValues(alpha: 0.5)
                      : Colors.transparent),
            width: 2.r,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ',
              style: TextStyle(
                fontSize: 13.r,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 140.r),
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.r,
                  fontWeight: FontWeight.w700,
                  color: (active || isFocused)
                      ? scheme.primary
                      : scheme.onSurface,
                ),
              ),
            ),
            SizedBox(width: 4.r),
            Icon(
              Symbols.expand_more_rounded,
              size: 16.r,
              color: scheme.onSurface.withValues(alpha: isFocused ? 0.9 : 0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClearChip(ThemeData theme, bool isFocused) {
    final scheme = theme.colorScheme;
    return GestureDetector(
      onTap: _clearFilters,
      child: Container(
        margin: EdgeInsets.only(right: 8.r),
        padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 8.r),
        decoration: BoxDecoration(
          color: isFocused
              ? scheme.primary.withValues(alpha: 0.18)
              : scheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isFocused ? scheme.primary : Colors.transparent,
            width: 2.r,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.filter_alt_off_rounded,
              size: 16.r,
              color: scheme.onSurface,
            ),
            SizedBox(width: 6.r),
            Text(
              AppLocale.searchClearFilters.getString(context),
              style: TextStyle(
                fontSize: 13.r,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The value picker overlay opened from a filter chip.
  ///
  /// Sized against the real viewport rather than a fixed `.r` height: 360.r is
  /// most of a 1080p handheld's screen, which pushed a long list (platforms,
  /// years) to full height and slid its title under the global tab strip. The
  /// overlay covers the whole tab area — which starts behind the header — so it
  /// carries the same 64.r header clearance the tab content does.
  Widget _buildFilterMenu(ThemeData theme, String key) {
    final scheme = theme.colorScheme;
    final labels = _menuLabels(key);
    final selected = _menuSelectedIndex(key);

    return Positioned.fill(
      child: GestureDetector(
        onTap: _cancelFilterMenu,
        child: ColoredBox(
          color: Colors.black.withValues(alpha: 0.6),
          child: LayoutBuilder(
            builder: (context, viewport) {
              final topInset = 64.r + 12.r;
              final available = viewport.maxHeight - topInset - 12.r;
              return Padding(
                padding: EdgeInsets.only(top: topInset, bottom: 12.r),
                child: Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: Container(
                      width: 320.r,
                      constraints: BoxConstraints(
                        maxHeight: math.max(
                          0,
                          math.min(available, viewport.maxHeight * 0.6),
                        ),
                      ),
                      padding: EdgeInsets.all(12.r),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(16.r),
                        border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.4),
                          width: 1.r,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: EdgeInsets.only(left: 4.r, bottom: 8.r),
                            child: Text(
                              _filterLabel(key),
                              style: TextStyle(
                                fontSize: 15.r,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface,
                              ),
                            ),
                          ),
                          Flexible(
                            child: ListView.builder(
                              controller: _menuScroll,
                              shrinkWrap: true,
                              itemExtent: _menuExtent.r,
                              itemCount: labels.length,
                              itemBuilder: (context, i) => _buildMenuOption(
                                theme,
                                key,
                                labels[i],
                                i,
                                selected,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildMenuOption(
    ThemeData theme,
    String key,
    String label,
    int index,
    int selected,
  ) {
    final scheme = theme.colorScheme;
    final isSelected = index == selected;
    return GestureDetector(
      onTap: () => _applyMenuIndex(key, index),
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 2.r),
        padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 8.r),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: isSelected ? scheme.primary : Colors.transparent,
            width: 2.r,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.r,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
            if (isSelected)
              Icon(Symbols.check_rounded, size: 16.r, color: scheme.primary),
          ],
        ),
      ),
    );
  }

  String _filterLabel(String key) => switch (key) {
    'platform' => AppLocale.filterPlatform.getString(context),
    'developer' => AppLocale.filterDeveloper.getString(context),
    'genre' => AppLocale.filterGenre.getString(context),
    'rating' => AppLocale.filterRating.getString(context),
    'year' => AppLocale.filterYear.getString(context),
    _ => key,
  };

  /// Display labels for a filter's menu, with "Any" at the head.
  List<String> _menuLabels(String key) {
    final any = AppLocale.filterAny.getString(context);
    if (key == 'rating') {
      return [any, ..._facets.ratings.map(_ratingDisplay)];
    }
    return [any, ..._menuOptions(key)];
  }

  /// A rating option: the plain 1..10 score games are filed under, not a
  /// "4+" threshold — each option matches one score, like every other filter.
  String _ratingDisplay(int score) => '★ $score';

  bool _isFilterActive(String key) => switch (key) {
    'platform' => _platform != null,
    'developer' => _developer != null,
    'genre' => _genre != null,
    'year' => _year != null,
    'rating' => _rating != null,
    _ => false,
  };

  String _filterValueLabel(String key) {
    final any = AppLocale.filterAny.getString(context);
    switch (key) {
      case 'platform':
        return _platform ?? any;
      case 'developer':
        return _developer ?? any;
      case 'genre':
        return _genre ?? any;
      case 'year':
        return _year ?? any;
      case 'rating':
        final t = _rating;
        return t == null ? any : _ratingDisplay(t);
      default:
        return any;
    }
  }

  Widget _buildResults(ThemeData theme) {
    if (_results.isEmpty) {
      return Center(
        child: Text(
          AppLocale.searchNoResults.getString(context),
          style: TextStyle(
            fontSize: 14.r,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _resultScroll,
      itemExtent: _resultExtent.r,
      itemCount: _results.length,
      itemBuilder: (context, index) => _buildResultTile(theme, index),
    );
  }

  Widget _buildResultTile(ThemeData theme, int index) {
    final scheme = theme.colorScheme;
    final g = _results[index];
    final isFocused = _region == _FocusRegion.results && _resultIndex == index;

    final subtitleParts = <String>[
      if ((g.systemShortName ?? g.systemRealName) != null)
        (g.systemShortName ?? g.systemRealName)!,
      if (_yearOf(g) != null) _yearOf(g)!,
      if (g.developer != null && g.developer!.trim().isNotEmpty)
        g.developer!.trim(),
    ];

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 3.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 10.r, vertical: 6.r),
        decoration: BoxDecoration(
          color: isFocused
              ? scheme.primary.withValues(alpha: 0.18)
              : scheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isFocused ? scheme.primary : Colors.transparent,
            width: 2.r,
          ),
        ),
        child: Row(
          children: [
            _buildBoxArt(theme, g),
            SizedBox(width: 10.r),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    g.realName ?? g.filename,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.r,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (subtitleParts.isNotEmpty)
                    Text(
                      subtitleParts.join('  •  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.r,
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
            if (g.rating != null && g.rating! > 0) ...[
              SizedBox(width: 8.r),
              Icon(Symbols.star_rounded, size: 14.r, color: scheme.primary),
              SizedBox(width: 2.r),
              Text(
                // Stored 0..20, shown out of 10 as everywhere else in the app.
                searchRatingScore(g.rating!).toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 12.r,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Resolves a result's box art through the same path the game list uses.
  ///
  /// [GameModel.getImagePath] is the canonical resolver: it covers NeoStation's
  /// own media folder, ROMs with complex extensions, and — critically — the
  /// read-time ES-DE `downloaded_media` fallback. A raw [FileProvider.getMediaPath]
  /// lookup sees none of those, so libraries scraped through ES-DE rendered as
  /// placeholders here while showing art everywhere else.
  ///
  /// Results are memoized per ROM: the list is virtualized over the whole
  /// library, so an unmemoized lookup re-stats several candidate paths every
  /// time a tile scrolls back into view.
  String? _resolveBoxArt(DatabaseGameModel g) {
    final folder = g.systemFolderName;
    if (folder == null || folder.isEmpty) return null;

    final key = '$folder/${g.filename}';
    if (_artCache.containsKey(key)) return _artCache[key];

    final resolved = GameModel.fromDatabaseModel(
      g,
    ).getImagePath(folder, 'box2d', context.read<FileProvider>());
    final exists = resolved.isNotEmpty && File(resolved).existsSync();
    return _artCache[key] = exists ? resolved : null;
  }

  /// Box art (box2d) thumbnail for a result, or a neutral placeholder when the
  /// game has no scraped cover.
  Widget _buildBoxArt(ThemeData theme, DatabaseGameModel g) {
    final scheme = theme.colorScheme;
    final artPath = _resolveBoxArt(g);

    return Container(
      width: 36.r,
      height: 46.r,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(
          color: scheme.onSurface.withValues(alpha: 0.12),
          width: 1.r,
        ),
      ),
      alignment: Alignment.center,
      child: artPath != null
          ? Image.file(
              File(artPath),
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            )
          : Icon(
              Symbols.videogame_asset_rounded,
              size: 18.r,
              color: scheme.onSurface.withValues(alpha: 0.35),
            ),
    );
  }
}
