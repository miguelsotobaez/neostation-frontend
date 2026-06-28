import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/database_game_model.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/repositories/game_repository.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/sync/sync_manager.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/utils/game_launch_utils.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/screens/game_screen/my_games_list.dart';

/// Library-wide ROM search & filter overlay.
///
/// Loads every game across all systems once, then filters in-memory by name
/// plus platform / developer / genre / rating / year. Reachable from the
/// Systems tab (header button or the gamepad Select button); selecting a
/// result launches it through the standard [launchGameWithDialog] flow.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  /// Pushes the search screen onto [context]'s navigator.
  static Future<void> open(BuildContext context) {
    return Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SearchScreen()));
  }

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

/// Which pane currently owns gamepad focus.
///
/// [action] is the per-result chooser overlay (Go to game / Play) shown after
/// a result is selected, so launching is always an explicit second step.
enum _FocusRegion { controls, results, action }

/// Ordered choices offered when a search result is selected.
enum _ResultAction { goTo, play }

/// Discrete rating thresholds offered in the rating filter (null == Any).
const List<double?> _ratingThresholds = [null, 3.0, 4.0, 4.5];

class _SearchScreenState extends State<SearchScreen> {
  late GamepadNavigation _gamepadNav;

  final TextEditingController _nameController = TextEditingController();
  final FocusNode _nameFocus = FocusNode();
  final ScrollController _resultScroll = ScrollController();
  final ScrollController _controlsScroll = ScrollController();
  final Map<int, GlobalKey> _controlKeys = {};

  bool _loading = true;
  List<DatabaseGameModel> _all = [];

  // Derived, sorted filter option sets (empty sets hide their control).
  List<String> _platforms = [];
  List<String> _developers = [];
  List<String> _genres = [];
  List<String> _years = [];

  // Active filter values (null == Any).
  String? _platform;
  String? _developer;
  String? _genre;
  String? _year;
  int _ratingIdx = 0;

  _FocusRegion _region = _FocusRegion.controls;
  int _controlIndex = 0;
  int _resultIndex = 0;

  // Active result-action chooser state (valid while _region == action).
  static const List<_ResultAction> _resultActions = [
    _ResultAction.goTo,
    _ResultAction.play,
  ];
  int _actionIndex = 0;
  DatabaseGameModel? _actionTarget;

  List<DatabaseGameModel> _results = [];

  static const double _resultExtent = 76;

  @override
  void initState() {
    super.initState();

    _gamepadNav = GamepadNavigation(
      onNavigateUp: _navigateUp,
      onNavigateDown: _navigateDown,
      onNavigateLeft: () => _cycleActiveFilter(-1),
      onNavigateRight: () => _cycleActiveFilter(1),
      onSelectItem: _handleSelect,
      onBack: _handleBack,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'search_screen',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });

    _loadGames();
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('search_screen');
    _gamepadNav.dispose();
    _nameController.dispose();
    _nameFocus.dispose();
    _resultScroll.dispose();
    _controlsScroll.dispose();
    super.dispose();
  }

  Future<void> _loadGames() async {
    final games = await GameRepository.getAllGames();
    if (!mounted) return;

    // Distinct, sorted option sets. Metadata-derived filters stay empty (and
    // therefore hidden) on an unscraped library.
    List<String> distinct(String? Function(DatabaseGameModel) pick) {
      final set = <String>{};
      for (final g in games) {
        final v = pick(g)?.trim();
        if (v != null && v.isNotEmpty) set.add(v);
      }
      final list = set.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return list;
    }

    setState(() {
      _all = games;
      _platforms = distinct((g) => g.systemRealName);
      _developers = distinct((g) => g.developer);
      _genres = distinct((g) => g.genre);
      _years = (() {
        final set = <String>{};
        for (final g in games) {
          final y = _yearOf(g);
          if (y != null) set.add(y);
        }
        final list = set.toList()..sort((a, b) => b.compareTo(a));
        return list;
      })();
      _loading = false;
      _recompute();
    });
  }

  /// Extracts a 4-digit year from a raw year / ISO release-date string.
  String? _yearOf(DatabaseGameModel g) {
    final raw = g.year?.trim();
    if (raw == null || raw.isEmpty) return null;
    final m = RegExp(r'(\d{4})').firstMatch(raw);
    return m?.group(1);
  }

  void _recompute() {
    final query = _nameController.text.trim().toLowerCase();
    final minRating = _ratingThresholdValue;

    _results =
        _all.where((g) {
          if (query.isNotEmpty) {
            final name = (g.realName ?? g.filename).toLowerCase();
            if (!name.contains(query)) return false;
          }
          if (_platform != null && g.systemRealName != _platform) return false;
          if (_developer != null && (g.developer?.trim() ?? '') != _developer) {
            return false;
          }
          if (_genre != null && (g.genre?.trim() ?? '') != _genre) return false;
          if (_year != null && _yearOf(g) != _year) return false;
          if (minRating != null && (g.rating ?? -1) < minRating) return false;
          return true;
        }).toList()..sort((a, b) {
          final an = (a.realName ?? a.filename).toLowerCase();
          final bn = (b.realName ?? b.filename).toLowerCase();
          return an.compareTo(bn);
        });

    if (_resultIndex >= _results.length) {
      _resultIndex = _results.isEmpty ? 0 : _results.length - 1;
    }
  }

  double? get _ratingThresholdValue => _ratingThresholds[_ratingIdx];

  // ── Control model ─────────────────────────────────────────────────────────
  // Index 0 = name field, then one row per visible filter, then Clear. Results
  // update live, so navigating Down past Clear flows straight into them.
  // Hidden (empty-option) filters are skipped entirely.

  /// Ordered keys of the currently visible filter rows.
  List<String> get _visibleFilters {
    return [
      if (_platforms.isNotEmpty) 'platform',
      'rating', // always available; thresholds are static
      if (_developers.isNotEmpty) 'developer',
      if (_genres.isNotEmpty) 'genre',
      if (_years.isNotEmpty) 'year',
    ];
  }

  /// Total focusable controls: name + filters + clear.
  int get _controlCount => 1 + _visibleFilters.length + 1;

  int get _clearIndex => 1 + _visibleFilters.length;

  // ── Navigation handlers ───────────────────────────────────────────────────

  void _navigateUp() {
    if (_region == _FocusRegion.action) {
      setState(
        () => _actionIndex =
            (_actionIndex - 1 + _resultActions.length) % _resultActions.length,
      );
    } else if (_region == _FocusRegion.results) {
      if (_resultIndex == 0) {
        // Top of the list — hand focus back to the controls column.
        setState(() => _region = _FocusRegion.controls);
        _ensureControlVisible();
      } else {
        setState(() => _resultIndex -= 1);
        _scrollResultIntoView();
      }
    } else {
      setState(
        () =>
            _controlIndex = (_controlIndex - 1 + _controlCount) % _controlCount,
      );
      _ensureControlVisible();
    }
    SfxService().playNavSound();
  }

  void _navigateDown() {
    if (_region == _FocusRegion.action) {
      setState(() => _actionIndex = (_actionIndex + 1) % _resultActions.length);
    } else if (_region == _FocusRegion.results) {
      if (_results.isEmpty) return;
      setState(
        () => _resultIndex = (_resultIndex + 1).clamp(0, _results.length - 1),
      );
      _scrollResultIntoView();
    } else if (_controlIndex >= _controlCount - 1) {
      // Past the last control — flow into the live results list.
      if (_results.isNotEmpty) {
        setState(() {
          _region = _FocusRegion.results;
          _resultIndex = _resultIndex.clamp(0, _results.length - 1);
        });
        _scrollResultIntoView();
      }
    } else {
      setState(() => _controlIndex += 1);
      _ensureControlVisible();
    }
    SfxService().playNavSound();
  }

  /// The filter key for the focused control row, or null if not a filter.
  String? get _focusedFilterKey {
    final filters = _visibleFilters;
    if (_controlIndex >= 1 && _controlIndex <= filters.length) {
      return filters[_controlIndex - 1];
    }
    return null;
  }

  void _cycleActiveFilter(int delta) {
    if (_region != _FocusRegion.controls) return;
    final key = _focusedFilterKey;
    if (key == null) return;

    setState(() {
      switch (key) {
        case 'platform':
          _platform = _cycleValue(_platforms, _platform, delta);
        case 'developer':
          _developer = _cycleValue(_developers, _developer, delta);
        case 'genre':
          _genre = _cycleValue(_genres, _genre, delta);
        case 'year':
          _year = _cycleValue(_years, _year, delta);
        case 'rating':
          _ratingIdx = (_ratingIdx + delta) % _ratingThresholds.length;
          if (_ratingIdx < 0) _ratingIdx += _ratingThresholds.length;
      }
      _recompute();
    });
    SfxService().playNavSound();
  }

  /// Cycles through [options] with an "Any" (null) slot at the head.
  String? _cycleValue(List<String> options, String? current, int delta) {
    // Combined list: [null, ...options]. Move by delta with wraparound.
    final len = options.length + 1;
    final currentIdx = current == null ? 0 : options.indexOf(current) + 1;
    var next = (currentIdx + delta) % len;
    if (next < 0) next += len;
    return next == 0 ? null : options[next - 1];
  }

  void _handleSelect() {
    if (_region == _FocusRegion.action) {
      _runResultAction(_resultActions[_actionIndex]);
      return;
    }

    if (_region == _FocusRegion.results) {
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
      return;
    }

    if (_controlIndex == 0) {
      // Name field: hand focus to the text field so the keyboard opens.
      _nameFocus.requestFocus();
      return;
    }
    if (_controlIndex == _clearIndex) {
      _clearFilters();
      return;
    }
    // A filter row: advance its value (same as Right).
    _cycleActiveFilter(1);
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
    if (_region == _FocusRegion.action) {
      setState(() => _region = _FocusRegion.results);
      return;
    }
    if (_region == _FocusRegion.results) {
      setState(() => _region = _FocusRegion.controls);
      return;
    }
    Navigator.of(context).maybePop();
  }

  void _clearFilters() {
    setState(() {
      _platform = null;
      _developer = null;
      _genre = null;
      _year = null;
      _ratingIdx = 0;
      _nameController.clear();
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
    await launchGameWithDialog(
      context: context,
      game: game,
      system: system,
      fileProvider: fileProvider,
      syncProvider: syncProvider,
      onGameClosed: () => GamepadNavigationManager.reactivate(),
      onLaunchFailed: (ctx, result) async {
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

  /// Closes search and opens the result's system game list with that game
  /// pre-selected, so the user lands on it in the normal browsing view.
  Future<void> _goToGame(DatabaseGameModel dbGame) async {
    final folder = dbGame.systemFolderName;
    if (folder == null || folder.isEmpty) return;

    final fileProvider = context.read<FileProvider>();
    final system = await SqliteService.getSystemByFolderName(folder);
    if (!mounted) return;

    final game = GameModel.fromDatabaseModel(dbGame);
    final navigator = Navigator.of(context);
    navigator.pop(); // close the search overlay
    navigator.push(
      MaterialPageRoute(
        builder: (_) => SystemGamesList(
          system: system,
          fileProvider: fileProvider,
          initialGameRomname: game.romname,
        ),
      ),
    );
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text(AppLocale.searchTitle.getString(context)),
        leading: IconButton(
          icon: const Icon(Symbols.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Padding(
                  padding: EdgeInsets.all(12.r),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 320.r, child: _buildControls(theme)),
                      SizedBox(width: 12.r),
                      Expanded(child: _buildResults(theme)),
                    ],
                  ),
                ),
                if (_region == _FocusRegion.action && _actionTarget != null)
                  _buildActionChooser(theme, _actionTarget!),
              ],
            ),
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

  Widget _buildControls(ThemeData theme) {
    final children = <Widget>[
      KeyedSubtree(key: _controlKey(0), child: _buildNameField(theme)),
      SizedBox(height: 8.r),
    ];

    final filters = _visibleFilters;
    final controlsFocused = _region == _FocusRegion.controls;
    for (var i = 0; i < filters.length; i++) {
      children.add(
        KeyedSubtree(
          key: _controlKey(i + 1),
          child: _buildFilterRow(
            theme,
            filters[i],
            controlsFocused && _controlIndex == i + 1,
          ),
        ),
      );
    }

    children.add(SizedBox(height: 8.r));
    children.add(
      KeyedSubtree(
        key: _controlKey(_clearIndex),
        child: _buildActionTile(
          theme,
          Symbols.filter_alt_off_rounded,
          AppLocale.searchClearFilters.getString(context),
          _region == _FocusRegion.controls && _controlIndex == _clearIndex,
        ),
      ),
    );

    return SingleChildScrollView(
      controller: _controlsScroll,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  /// Stable per-index keys so the focused control can be scrolled into view.
  GlobalKey _controlKey(int index) =>
      _controlKeys.putIfAbsent(index, () => GlobalKey());

  /// Keeps the focused filter/control visible when the column overflows.
  void _ensureControlVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _controlKeys[_controlIndex]?.currentContext;
      if (ctx == null || !mounted) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  Widget _buildNameField(ThemeData theme) {
    final focused = _region == _FocusRegion.controls && _controlIndex == 0;
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

  Widget _buildFilterRow(ThemeData theme, String key, bool isFocused) {
    final scheme = theme.colorScheme;
    final label = switch (key) {
      'platform' => AppLocale.filterPlatform.getString(context),
      'developer' => AppLocale.filterDeveloper.getString(context),
      'genre' => AppLocale.filterGenre.getString(context),
      'rating' => AppLocale.filterRating.getString(context),
      'year' => AppLocale.filterYear.getString(context),
      _ => key,
    };
    final value = _filterValueLabel(key);

    return Container(
      margin: EdgeInsets.symmetric(vertical: 4.r),
      padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 10.r),
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
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.r,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          Icon(
            Symbols.chevron_left_rounded,
            size: 16.r,
            color: scheme.onSurface.withValues(alpha: isFocused ? 0.9 : 0.3),
          ),
          SizedBox(width: 4.r),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 150.r),
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13.r,
                fontWeight: FontWeight.w700,
                color: isFocused ? scheme.primary : scheme.onSurface,
              ),
            ),
          ),
          SizedBox(width: 4.r),
          Icon(
            Symbols.chevron_right_rounded,
            size: 16.r,
            color: scheme.onSurface.withValues(alpha: isFocused ? 0.9 : 0.3),
          ),
        ],
      ),
    );
  }

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
        final t = _ratingThresholdValue;
        return t == null ? any : '★ ${t.toStringAsFixed(t == 4.5 ? 1 : 0)}+';
      default:
        return any;
    }
  }

  Widget _buildActionTile(
    ThemeData theme,
    IconData icon,
    String label,
    bool isFocused,
  ) {
    final scheme = theme.colorScheme;
    return Container(
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
          Icon(icon, size: 18.r, color: scheme.onSurface),
          SizedBox(width: 8.r),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13.r,
                fontWeight: FontWeight.w700,
                color: scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(left: 4.r, bottom: 6.r),
          child: Text(
            AppLocale.searchResultsCount
                .getString(context)
                .replaceFirst('{count}', '${_results.length}'),
            style: TextStyle(
              fontSize: 12.r,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: _resultScroll,
            itemExtent: _resultExtent.r,
            itemCount: _results.length,
            itemBuilder: (context, index) => _buildResultTile(theme, index),
          ),
        ),
      ],
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
                g.rating!.toStringAsFixed(1),
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

  /// Box art (box2d) thumbnail for a result, or a neutral placeholder when the
  /// game has no scraped cover.
  Widget _buildBoxArt(ThemeData theme, DatabaseGameModel g) {
    final scheme = theme.colorScheme;
    final folder = g.systemFolderName;
    File? art;
    if (folder != null && folder.isNotEmpty) {
      final fileProvider = context.read<FileProvider>();
      for (final ext in const ['png', 'jpg']) {
        final candidate = File(
          fileProvider.getMediaPath(folder, 'box2d', g.romname, ext),
        );
        if (candidate.existsSync()) {
          art = candidate;
          break;
        }
      }
    }

    return Container(
      width: 48.r,
      height: 60.r,
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
      child: art != null
          ? Image.file(
              art,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
            )
          : Icon(
              Symbols.videogame_asset_rounded,
              size: 22.r,
              color: scheme.onSurface.withValues(alpha: 0.35),
            ),
    );
  }
}
