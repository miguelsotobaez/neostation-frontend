import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/ra_game_list_entry.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/repositories/retro_achievements_repository.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';

/// Lets the user correct the RetroAchievements match for a single game.
///
/// Hashing cannot reach every dump: hacks, translations, bad dumps and disc
/// images RetroAchievements never registered will not match no matter how good
/// the algorithm is. This searches the bundled snapshot by title so the user
/// can point the game at the right set by hand, and marks the row so a later
/// automatic pass leaves their choice alone.
///
/// Pops `true` when the match changed.
class RaMatchPickerDialog extends StatefulWidget {
  final GameModel game;
  final SystemModel system;

  /// Currently stored RetroAchievements game id, if any.
  final int? currentGameId;

  /// Whether the current match was set by hand, which enables the reset row.
  final bool isManualMatch;

  const RaMatchPickerDialog({
    super.key,
    required this.game,
    required this.system,
    this.currentGameId,
    this.isManualMatch = false,
  });

  static Future<bool> show(
    BuildContext context, {
    required GameModel game,
    required SystemModel system,
    int? currentGameId,
    bool isManualMatch = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RaMatchPickerDialog(
        game: game,
        system: system,
        currentGameId: currentGameId,
        isManualMatch: isManualMatch,
      ),
    );
    return result ?? false;
  }

  @override
  State<RaMatchPickerDialog> createState() => _RaMatchPickerDialogState();
}

class _RaMatchPickerDialogState extends State<RaMatchPickerDialog> {
  static final _log = LoggerService.instance;
  static const String _layerId = 'ra_match_picker_dialog';
  static const Duration _searchDebounce = Duration(milliseconds: 300);

  late final GamepadNavigation _gamepadNav;
  final TextEditingController _queryController = TextEditingController();
  final FocusNode _queryFocus = FocusNode();
  final ScrollController _scrollController = ScrollController();

  List<RaGameListEntry> _results = [];
  bool _isSearching = false;
  bool _isFieldFocused = false;
  int _selectedIndex = 0;
  Timer? _debounce;

  /// Index of the "use automatic matching" row, or null when it is not shown.
  int? get _resetIndex => widget.isManualMatch ? _results.length + 1 : null;

  int get _itemCount => _results.length + (widget.isManualMatch ? 2 : 1);

  @override
  void initState() {
    super.initState();

    _queryController.text = _initialQuery();
    _queryFocus.addListener(() {
      if (!mounted) return;
      setState(() => _isFieldFocused = _queryFocus.hasFocus);
    });

    _gamepadNav = GamepadNavigation(
      onNavigateUp: _moveUp,
      onNavigateDown: _moveDown,
      onSelectItem: _activateSelection,
      onBack: _handleBack,
      isTextFieldFocused: () => _queryFocus.hasFocus,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        _layerId,
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });

    _search(_queryController.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    GamepadNavigationManager.popLayer(_layerId);
    _gamepadNav.dispose();
    _queryController.dispose();
    _queryFocus.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Best first guess at what the user is looking for: the display name with
  /// region tags and dump markers stripped, which is how RA titles read.
  String _initialQuery() {
    final raw = widget.game.name.isNotEmpty
        ? widget.game.name
        : widget.game.romname;
    return raw
        .replaceAll(RegExp(r'\.[A-Za-z0-9]{1,5}$'), '')
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s*\[[^\]]*\]'), '')
        .trim();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_searchDebounce, () => _search(value));
  }

  Future<void> _search(String query) async {
    final consoleId = widget.system.raId;
    if (consoleId == null || consoleId.isEmpty) {
      setState(() => _results = []);
      return;
    }

    setState(() => _isSearching = true);
    try {
      final results = await RetroAchievementsRepository.searchRaGamesByTitle(
        consoleId,
        query,
      );
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
        _selectedIndex = _selectedIndex.clamp(0, _itemCount - 1);
      });
    } catch (e) {
      _log.e('RA match search failed: $e');
      if (!mounted) return;
      setState(() {
        _results = [];
        _isSearching = false;
      });
    }
  }

  // ── Gamepad ───────────────────────────────────────────────────────────────

  void _moveUp() {
    if (_queryFocus.hasFocus) return;
    if (_selectedIndex == 0) return;
    setState(() => _selectedIndex--);
    _scrollToSelection();
  }

  void _moveDown() {
    if (_queryFocus.hasFocus) return;
    if (_selectedIndex >= _itemCount - 1) return;
    setState(() => _selectedIndex++);
    _scrollToSelection();
  }

  void _activateSelection() {
    if (_queryFocus.hasFocus) {
      // Enter/A while typing commits the search and returns to list navigation.
      _queryFocus.unfocus();
      _debounce?.cancel();
      _search(_queryController.text);
      return;
    }

    if (_selectedIndex == 0) {
      _queryFocus.requestFocus();
      return;
    }

    if (_selectedIndex == _resetIndex) {
      _clearManualMatch();
      return;
    }

    final entry = _results.elementAtOrNull(_selectedIndex - 1);
    if (entry != null) _applyMatch(entry);
  }

  /// B leaves the text field first, and only closes the dialog once the field
  /// is no longer focused — the app-wide way out of text entry.
  void _handleBack() {
    if (_queryFocus.hasFocus) {
      _queryFocus.unfocus();
      return;
    }
    if (mounted) Navigator.of(context).pop(false);
  }

  void _scrollToSelection() {
    if (!_scrollController.hasClients) return;
    // Rows are a fixed height, so the offset can be computed directly rather
    // than measured.
    final target = ((_selectedIndex - 1) * 44.r).clamp(
      0.0,
      _scrollController.position.maxScrollExtent,
    );
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
    );
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _applyMatch(RaGameListEntry entry) async {
    final romPath = widget.game.romPath;
    if (romPath == null || romPath.isEmpty) return;

    SfxService().playNavSound();
    await RetroAchievementsRepository.setManualRomRaMatch(
      romPath,
      entry.gameId,
    );
    _log.i('RA match set by hand: ${widget.game.name} -> ${entry.gameId}');
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _clearManualMatch() async {
    final romPath = widget.game.romPath;
    if (romPath == null || romPath.isEmpty) return;

    SfxService().playNavSound();
    await RetroAchievementsRepository.clearManualRomRaMatch(romPath);
    if (mounted) Navigator.of(context).pop(true);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return Dialog(
      backgroundColor: theme.cardColor,
      insetPadding: EdgeInsets.symmetric(horizontal: 24.r, vertical: 24.r),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
        side: BorderSide(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Container(
        width: size.width * 0.6,
        constraints: BoxConstraints(maxHeight: size.height * 0.7),
        padding: EdgeInsets.all(12.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTitle(theme),
            SizedBox(height: 10.r),
            _buildSearchField(theme),
            SizedBox(height: 8.r),
            Flexible(child: _buildResults(theme)),
            if (widget.isManualMatch) ...[
              SizedBox(height: 6.r),
              _buildResetRow(theme),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTitle(ThemeData theme) {
    return Row(
      children: [
        Icon(
          Symbols.emoji_events_rounded,
          color: theme.colorScheme.primary,
          size: 18.r,
        ),
        SizedBox(width: 8.r),
        Expanded(
          child: Text(
            AppLocale.raFixMatchTitle.getString(context),
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 13.r,
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          widget.system.realName,
          style: TextStyle(
            fontSize: 10.r,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    final selected = _selectedIndex == 0;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(
          color: selected || _isFieldFocused
              ? theme.colorScheme.primary
              : theme.colorScheme.outline.withValues(alpha: 0.4),
          width: selected || _isFieldFocused ? 2.r : 1.r,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 8.r),
      child: Row(
        children: [
          Icon(
            Symbols.search_rounded,
            size: 14.r,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
          SizedBox(width: 6.r),
          Expanded(
            child: TextField(
              controller: _queryController,
              focusNode: _queryFocus,
              onChanged: _onQueryChanged,
              onTap: () => setState(() => _selectedIndex = 0),
              style: TextStyle(
                fontSize: 12.r,
                color: theme.colorScheme.onSurface,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10.r),
                hintText: AppLocale.raFixMatchSearchHint.getString(context),
                hintStyle: TextStyle(
                  fontSize: 12.r,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
          if (_isSearching)
            SizedBox(
              width: 12.r,
              height: 12.r,
              child: CircularProgressIndicator(strokeWidth: 1.5.r),
            ),
        ],
      ),
    );
  }

  Widget _buildResults(ThemeData theme) {
    if (_results.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 20.r),
        child: Center(
          child: Text(
            AppLocale.raFixMatchNoResults.getString(context),
            style: TextStyle(
              fontSize: 11.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      shrinkWrap: true,
      physics: const ClampingScrollPhysics(),
      itemCount: _results.length,
      itemBuilder: (context, i) {
        final entry = _results[i];
        return _RaMatchRow(
          entry: entry,
          selected: _selectedIndex == i + 1,
          isCurrent: entry.gameId == widget.currentGameId,
          onTap: () {
            setState(() => _selectedIndex = i + 1);
            _applyMatch(entry);
          },
        );
      },
    );
  }

  Widget _buildResetRow(ThemeData theme) {
    final selected = _selectedIndex == _resetIndex;
    return InkWell(
      onTap: _clearManualMatch,
      borderRadius: BorderRadius.circular(6.r),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 8.r),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 2.r,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Symbols.restart_alt_rounded,
              size: 14.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            SizedBox(width: 6.r),
            Text(
              AppLocale.raFixMatchUseAutomatic.getString(context),
              style: TextStyle(
                fontSize: 11.r,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A single searchable RetroAchievements title.
class _RaMatchRow extends StatelessWidget {
  final RaGameListEntry entry;
  final bool selected;
  final bool isCurrent;
  final VoidCallback onTap;

  const _RaMatchRow({
    required this.entry,
    required this.selected,
    required this.isCurrent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = entry.numAchievements;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6.r),
      child: Container(
        height: 44.r,
        padding: EdgeInsets.symmetric(horizontal: 8.r),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6.r),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 2.r,
          ),
        ),
        child: Row(
          children: [
            if (isCurrent) ...[
              Icon(
                Symbols.check_circle_rounded,
                size: 14.r,
                color: theme.colorScheme.primary,
              ),
              SizedBox(width: 6.r),
            ],
            Expanded(
              child: Text(
                entry.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.r,
                  color: theme.colorScheme.onSurface,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            if (count != null && count > 0) ...[
              SizedBox(width: 8.r),
              Text(
                AppLocale.raFixMatchAchievements
                    .getString(context)
                    .replaceFirst('{count}', count.toString()),
                style: TextStyle(
                  fontSize: 9.r,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
