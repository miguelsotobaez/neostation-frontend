import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/repositories/game_repository.dart';
import 'package:neostation/repositories/system_repository.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/widgets/core_footer.dart';
import 'package:neostation/widgets/search_filter_controls.dart';

/// Which band currently holds gamepad focus.
enum _FocusBand { search, systemFilter, selectionFilter, results, filterMenu }

enum _MembershipFilter { all, selected, unselected }

enum _FilterMenuKind { system, membership }

/// Full-screen dialog to search, filter by system, and toggle inclusion of games
/// in a collection. Structured with standard focus bands matching SearchScreen.
class CollectionAddGamesDialog extends StatefulWidget {
  final String collectionName;
  final Set<String> initialSelectedRomPaths;
  final ValueChanged<Set<String>> onSave;

  const CollectionAddGamesDialog({
    super.key,
    required this.collectionName,
    required this.initialSelectedRomPaths,
    required this.onSave,
  });

  static Future<void> show({
    required BuildContext context,
    required String collectionName,
    required Set<String> initialSelectedRomPaths,
    required ValueChanged<Set<String>> onSave,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CollectionAddGamesDialog(
        collectionName: collectionName,
        initialSelectedRomPaths: initialSelectedRomPaths,
        onSave: onSave,
      ),
    );
  }

  @override
  State<CollectionAddGamesDialog> createState() =>
      _CollectionAddGamesDialogState();
}

class _CollectionAddGamesDialogState extends State<CollectionAddGamesDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _filterScrollController = ScrollController();
  late final GamepadNavigation _gamepadNav;

  List<GameModel> _allGames = [];
  List<SystemModel> _systems = [];
  late Set<String> _selectedRomPaths;

  String _searchQuery = '';
  String? _selectedSystemId; // null = all systems
  _MembershipFilter _membershipFilter = _MembershipFilter.all;
  bool _isLoading = true;

  _FocusBand _focusBand = _FocusBand.results;
  int _focusedGameIndex = 0;
  int _filterMenuIndex = 0;
  String? _filterMenuOriginalSystemId;
  _MembershipFilter _filterMenuOriginalMembership = _MembershipFilter.all;
  _FilterMenuKind _filterMenuKind = _FilterMenuKind.system;

  String get _selectedSystemLabel {
    if (_selectedSystemId == null) {
      return AppLocale.allSystems.getString(context);
    }
    final matches = _systems.where(
      (system) => system.folderName == _selectedSystemId,
    );
    return matches.isEmpty ? _selectedSystemId! : matches.first.realName;
  }

  String get _membershipFilterLabel => switch (_membershipFilter) {
    _MembershipFilter.all => AppLocale.filterAny.getString(context),
    _MembershipFilter.selected => AppLocale.selectedGames.getString(context),
    _MembershipFilter.unselected => AppLocale.unselectedGames.getString(
      context,
    ),
  };

  List<GameModel> get _filteredGames {
    return _allGames.where((game) {
      if (_selectedSystemId != null &&
          game.systemFolderName != _selectedSystemId) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final query = _searchQuery.toLowerCase();
        final name = game.name.toLowerCase();
        final filename = game.romname.toLowerCase();
        if (!name.contains(query) && !filename.contains(query)) {
          return false;
        }
      }
      final selected = _selectedRomPaths.contains(game.romPath);
      if (_membershipFilter == _MembershipFilter.selected && !selected) {
        return false;
      }
      if (_membershipFilter == _MembershipFilter.unselected && selected) {
        return false;
      }
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _selectedRomPaths = Set<String>.from(widget.initialSelectedRomPaths);
    _searchFocusNode.onKeyEvent = (node, event) {
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.escape) {
        _handleBack();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    _loadData();
    _setupGamepad();
  }

  Future<void> _loadData() async {
    try {
      final dbGames = await GameRepository.getAllGames();
      final systems = await SystemRepository.getAllSystems();

      if (!mounted) return;
      setState(() {
        _allGames = dbGames
            .where((g) => !g.isHidden)
            .map((g) => GameModel.fromDatabaseModel(g))
            .toList();
        _systems = systems.where((s) => s.romCount > 0).toList();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _setupGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: _handleNavigateUp,
      onNavigateDown: _handleNavigateDown,
      onNavigateLeft: _handleNavigateLeft,
      onNavigateRight: _handleNavigateRight,
      onSelectItem: _handleSelect,
      onBack: _handleBack,
      onXButton: _handleXButton,
      onFavorite: _finishAndSave,
      onLeftBumper: () => _cycleSystemFilter(-1),
      onRightBumper: () => _cycleSystemFilter(1),
      onPreviousTab: () => _cycleSystemFilter(-1),
      onNextTab: () => _cycleSystemFilter(1),
      isTextFieldFocused: () => _searchFocusNode.hasFocus,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'collection_add_games_dialog',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
        modal: true,
      );
    });
  }

  @override
  void dispose() {
    _gamepadNav.dispose();
    GamepadNavigationManager.popLayer('collection_add_games_dialog');
    _searchController.dispose();
    _searchFocusNode.dispose();
    _scrollController.dispose();
    _filterScrollController.dispose();
    super.dispose();
  }

  void _handleNavigateUp() {
    if (_focusBand == _FocusBand.filterMenu) {
      _moveFilterMenu(-1);
      return;
    }
    if (_focusBand == _FocusBand.results) {
      if (_focusedGameIndex > 0) {
        SfxService().playNavSound();
        setState(() => _focusedGameIndex--);
        _scrollToFocusedGame();
      } else {
        SfxService().playNavSound();
        setState(() => _focusBand = _FocusBand.systemFilter);
      }
    } else if (_focusBand == _FocusBand.systemFilter ||
        _focusBand == _FocusBand.selectionFilter) {
      SfxService().playNavSound();
      setState(() => _focusBand = _FocusBand.search);
    }
  }

  void _handleNavigateDown() {
    if (_focusBand == _FocusBand.filterMenu) {
      _moveFilterMenu(1);
      return;
    }
    if (_focusBand == _FocusBand.search) {
      SfxService().playNavSound();
      _searchFocusNode.unfocus();
      setState(() => _focusBand = _FocusBand.systemFilter);
    } else if (_focusBand == _FocusBand.systemFilter ||
        _focusBand == _FocusBand.selectionFilter) {
      if (_filteredGames.isNotEmpty) {
        SfxService().playNavSound();
        setState(() => _focusBand = _FocusBand.results);
        _scrollToFocusedGame();
      }
    } else if (_focusBand == _FocusBand.results) {
      final maxIdx = _filteredGames.length - 1;
      if (_focusedGameIndex < maxIdx) {
        SfxService().playNavSound();
        setState(() => _focusedGameIndex++);
        _scrollToFocusedGame();
      }
    }
  }

  void _handleNavigateLeft() {
    if (_focusBand == _FocusBand.selectionFilter) {
      SfxService().playNavSound();
      setState(() => _focusBand = _FocusBand.systemFilter);
    } else if (_focusBand == _FocusBand.results) {
      _handlePageUp();
    }
  }

  void _handleNavigateRight() {
    if (_focusBand == _FocusBand.systemFilter) {
      SfxService().playNavSound();
      setState(() => _focusBand = _FocusBand.selectionFilter);
    } else if (_focusBand == _FocusBand.results) {
      _handlePageDown();
    }
  }

  void _handlePageUp() {
    if (_filteredGames.isEmpty) return;
    const pageSize = 8;
    final newIdx = math.max(0, _focusedGameIndex - pageSize);
    if (newIdx != _focusedGameIndex) {
      SfxService().playNavSound();
      setState(() => _focusedGameIndex = newIdx);
      _scrollToFocusedGame();
    }
  }

  void _handlePageDown() {
    if (_filteredGames.isEmpty) return;
    const pageSize = 8;
    final maxIdx = _filteredGames.length - 1;
    final newIdx = math.min(maxIdx, _focusedGameIndex + pageSize);
    if (newIdx != _focusedGameIndex) {
      SfxService().playNavSound();
      setState(() => _focusedGameIndex = newIdx);
      _scrollToFocusedGame();
    }
  }

  void _handleSelect() {
    switch (_focusBand) {
      case _FocusBand.search:
        _searchFocusNode.requestFocus();
      case _FocusBand.systemFilter:
        _openFilterMenu(_FilterMenuKind.system);
      case _FocusBand.selectionFilter:
        _openFilterMenu(_FilterMenuKind.membership);
      case _FocusBand.results:
        _toggleFocusedGame();
      case _FocusBand.filterMenu:
        _closeFilterMenu(commit: true);
    }
  }

  List<String?> get _systemFilterValues => [
    null,
    ..._systems.map((system) => system.folderName),
  ];

  void _openFilterMenu(_FilterMenuKind kind) {
    setState(() {
      _filterMenuKind = kind;
      _filterMenuOriginalSystemId = _selectedSystemId;
      _filterMenuOriginalMembership = _membershipFilter;
      _filterMenuIndex = kind == _FilterMenuKind.system
          ? _systemFilterValues.indexOf(_selectedSystemId)
          : _membershipFilter.index;
      _focusBand = _FocusBand.filterMenu;
    });
    _scrollFilterMenuIntoView();
    SfxService().playNavSound();
  }

  void _moveFilterMenu(int delta) {
    final count = _filterMenuKind == _FilterMenuKind.system
        ? _systemFilterValues.length
        : _MembershipFilter.values.length;
    if (count == 0) return;
    setState(() {
      _filterMenuIndex = (_filterMenuIndex + delta + count) % count;
      if (_filterMenuKind == _FilterMenuKind.system) {
        _selectedSystemId = _systemFilterValues[_filterMenuIndex];
      } else {
        _membershipFilter = _MembershipFilter.values[_filterMenuIndex];
      }
      _focusedGameIndex = 0;
    });
    _scrollFilterMenuIntoView();
    SfxService().playNavSound();
  }

  void _closeFilterMenu({required bool commit}) {
    setState(() {
      if (!commit) {
        _selectedSystemId = _filterMenuOriginalSystemId;
        _membershipFilter = _filterMenuOriginalMembership;
      }
      _focusedGameIndex = 0;
      _focusBand = _filterMenuKind == _FilterMenuKind.system
          ? _FocusBand.systemFilter
          : _FocusBand.selectionFilter;
    });
  }

  void _scrollFilterMenuIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_filterScrollController.hasClients) return;
      const extent = 44.0;
      final position = _filterScrollController.position;
      final target =
          (_filterMenuIndex * extent.r) -
          (position.viewportDimension - extent.r) / 2;
      _filterScrollController.animateTo(
        target.clamp(0.0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    });
  }

  void _cycleSystemFilter(int direction) {
    final values = _systemFilterValues;
    if (values.length < 2) return;
    final current = values.indexOf(_selectedSystemId);
    final next = (current + direction + values.length) % values.length;
    SfxService().playNavSound();
    setState(() {
      _selectedSystemId = values[next];
      _focusedGameIndex = 0;
      if (_filteredGames.isEmpty) _focusBand = _FocusBand.search;
    });
    _scrollToFocusedGame();
  }

  void _handleXButton() {
    if (_searchQuery.isNotEmpty) {
      SfxService().playNavSound();
      setState(() {
        _searchController.clear();
        _searchQuery = '';
        _focusedGameIndex = 0;
      });
    }
  }

  void _toggleFocusedGame() {
    final games = _filteredGames;
    if (_focusedGameIndex < 0 || _focusedGameIndex >= games.length) return;

    final game = games[_focusedGameIndex];
    final romPath = game.romPath ?? '';
    if (romPath.isEmpty) return;

    SfxService().playEnterSound();
    setState(() {
      if (_selectedRomPaths.contains(romPath)) {
        _selectedRomPaths.remove(romPath);
      } else {
        _selectedRomPaths.add(romPath);
      }
    });
  }

  void _scrollToFocusedGame() {
    if (!_scrollController.hasClients) return;
    const itemHeight = 64.0;
    final targetOffset = _focusedGameIndex * itemHeight;
    final currentOffset = _scrollController.offset;
    final viewportHeight = _scrollController.position.viewportDimension;

    if (targetOffset < currentOffset) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    } else if (targetOffset + itemHeight > currentOffset + viewportHeight) {
      _scrollController.animateTo(
        targetOffset + itemHeight - viewportHeight,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  void _finishAndSave() {
    SfxService().playEnterSound();
    widget.onSave(_selectedRomPaths);
    Navigator.of(context).pop();
  }

  void _handleBack() {
    if (_searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
      return;
    }
    if (_focusBand == _FocusBand.filterMenu) {
      _closeFilterMenu(commit: false);
      return;
    }
    SfxService().playBackSound();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final filtered = _filteredGames;

    return Dialog.fullscreen(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Top App Bar
                Container(
                  padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 8.h),
                  decoration: BoxDecoration(
                    color: theme.cardColor.withValues(alpha: 0.6),
                    border: Border(
                      bottom: BorderSide(
                        color: theme.dividerColor.withValues(alpha: 0.2),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.playlist_add_rounded,
                        color: primaryColor,
                        size: 24.r,
                      ),
                      SizedBox(width: 10.w),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocale.addGames.getString(context),
                            style: TextStyle(
                              fontSize: 18.sp,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            widget.collectionName,
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: primaryColor,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        '${_selectedRomPaths.length} ${AppLocale.selected.getString(context).toLowerCase()}',
                        style: TextStyle(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: primaryColor,
                        ),
                      ),
                    ],
                  ),
                ),

                // Search Bar & System Filters Row
                Padding(
                  padding: EdgeInsets.fromLTRB(20.w, 8.h, 20.w, 8.h),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        textInputAction: TextInputAction.done,
                        style: TextStyle(fontSize: 14.sp),
                        decoration: InputDecoration(
                          hintText: AppLocale.searchGames.getString(context),
                          prefixIcon: const Icon(Symbols.search_rounded),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Symbols.close_rounded),
                                  onPressed: () {
                                    setState(() {
                                      _searchController.clear();
                                      _searchQuery = '';
                                      _focusedGameIndex = 0;
                                    });
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: theme.cardColor.withValues(alpha: 0.4),
                          contentPadding: EdgeInsets.symmetric(vertical: 10.h),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide(
                              color: (_focusBand == _FocusBand.search)
                                  ? primaryColor
                                  : theme.dividerColor.withValues(alpha: 0.2),
                              width: (_focusBand == _FocusBand.search)
                                  ? 2.r
                                  : 1.r,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12.r),
                            borderSide: BorderSide(
                              color: (_focusBand == _FocusBand.search)
                                  ? primaryColor
                                  : theme.dividerColor.withValues(alpha: 0.2),
                              width: (_focusBand == _FocusBand.search)
                                  ? 2.r
                                  : 1.r,
                            ),
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _focusBand = _FocusBand.search;
                            _searchQuery = val.trim();
                            _focusedGameIndex = 0;
                          });
                        },
                        onSubmitted: (_) => _searchFocusNode.unfocus(),
                      ),
                      SizedBox(height: 6.h),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            SearchFilterChip(
                              label: AppLocale.systems.getString(context),
                              value: _selectedSystemLabel,
                              isFocused: _focusBand == _FocusBand.systemFilter,
                              isActive: _selectedSystemId != null,
                              onTap: () {
                                _searchFocusNode.unfocus();
                                setState(
                                  () => _focusBand = _FocusBand.systemFilter,
                                );
                                _openFilterMenu(_FilterMenuKind.system);
                              },
                            ),
                            SearchFilterChip(
                              label: AppLocale.selection.getString(context),
                              value: _membershipFilterLabel,
                              isFocused:
                                  _focusBand == _FocusBand.selectionFilter,
                              isActive:
                                  _membershipFilter != _MembershipFilter.all,
                              onTap: () {
                                _searchFocusNode.unfocus();
                                setState(
                                  () => _focusBand = _FocusBand.selectionFilter,
                                );
                                _openFilterMenu(_FilterMenuKind.membership);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // Game List
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Symbols.search_off_rounded,
                                size: 48.r,
                                color: theme.hintColor,
                              ),
                              SizedBox(height: 12.h),
                              Text(
                                AppLocale.noGamesFound.getString(context),
                                style: TextStyle(
                                  fontSize: 16.sp,
                                  color: theme.hintColor,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: filtered.length,
                          itemExtent: 64.h,
                          itemBuilder: (context, index) {
                            final game = filtered[index];
                            final romPath = game.romPath ?? '';
                            final isSelected = _selectedRomPaths.contains(
                              romPath,
                            );
                            final isFocused =
                                _focusBand == _FocusBand.results &&
                                index == _focusedGameIndex;

                            return MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _focusBand = _FocusBand.results;
                                    _focusedGameIndex = index;
                                  });
                                  _toggleFocusedGame();
                                },
                                child: Container(
                                  margin: EdgeInsets.symmetric(
                                    horizontal: 16.w,
                                    vertical: 3.h,
                                  ),
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 14.w,
                                    vertical: 8.h,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isFocused
                                        ? primaryColor.withValues(alpha: 0.18)
                                        : (isSelected
                                              ? primaryColor.withValues(
                                                  alpha: 0.08,
                                                )
                                              : theme.cardColor.withValues(
                                                  alpha: 0.3,
                                                )),
                                    borderRadius: BorderRadius.circular(10.r),
                                    border: Border.all(
                                      color: isFocused
                                          ? primaryColor
                                          : (isSelected
                                                ? primaryColor.withValues(
                                                    alpha: 0.4,
                                                  )
                                                : Colors.transparent),
                                      width: isFocused ? 2.r : 1.r,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Checkbox(
                                        value: isSelected,
                                        activeColor: primaryColor,
                                        onChanged: (_) {
                                          setState(() {
                                            _focusBand = _FocusBand.results;
                                            _focusedGameIndex = index;
                                          });
                                          _toggleFocusedGame();
                                        },
                                      ),
                                      SizedBox(width: 8.w),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              game.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14.sp,
                                                fontWeight:
                                                    isSelected || isFocused
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                                color: isFocused
                                                    ? primaryColor
                                                    : theme
                                                          .textTheme
                                                          .bodyLarge
                                                          ?.color,
                                              ),
                                            ),
                                            if (game.developer.isNotEmpty)
                                              Text(
                                                game.developer,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 11.sp,
                                                  color: theme.hintColor,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      if (game.systemRealName != null &&
                                          game.systemRealName!.isNotEmpty)
                                        Container(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 8.w,
                                            vertical: 3.h,
                                          ),
                                          decoration: BoxDecoration(
                                            color: theme.cardColor.withValues(
                                              alpha: 0.8,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              6.r,
                                            ),
                                          ),
                                          child: Text(
                                            game.systemRealName!,
                                            style: TextStyle(
                                              fontSize: 11.sp,
                                              color: theme.hintColor,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
                _AddGamesFooter(
                  collectionName: widget.collectionName,
                  selectedCount: _selectedRomPaths.length,
                  onCancel: _handleBack,
                  onSave: _finishAndSave,
                ),
              ],
            ),
            if (_focusBand == _FocusBand.filterMenu)
              Positioned.fill(child: _buildFilterMenu(theme)),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterMenu(ThemeData theme) {
    final scheme = theme.colorScheme;
    final values = _filterMenuKind == _FilterMenuKind.system
        ? _systemFilterValues
        : _MembershipFilter.values;
    final labels = _filterMenuKind == _FilterMenuKind.system
        ? <String>[
            AppLocale.allSystems.getString(context),
            ..._systems.map((system) => system.realName),
          ]
        : <String>[
            AppLocale.filterAny.getString(context),
            AppLocale.selectedGames.getString(context),
            AppLocale.unselectedGames.getString(context),
          ];

    return GestureDetector(
      onTap: () => _closeFilterMenu(commit: false),
      child: ColoredBox(
        color: Colors.black.withValues(alpha: 0.6),
        child: CustomSingleChildLayout(
          delegate: SearchFilterMenuLayout(
            topInset: 12.r,
            bottomInset: kCoreFooterHeight.r + 12.r,
          ),
          child: GestureDetector(
            onTap: () {},
            child: Container(
              width: 320.r,
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
                      (_filterMenuKind == _FilterMenuKind.system
                              ? AppLocale.systems
                              : AppLocale.selection)
                          .getString(context),
                      style: TextStyle(
                        fontSize: 15.r,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.builder(
                      controller: _filterScrollController,
                      shrinkWrap: true,
                      itemExtent: 44.r,
                      itemCount: labels.length,
                      itemBuilder: (context, index) => SearchFilterMenuOption(
                        label: labels[index],
                        isSelected: index == _filterMenuIndex,
                        onTap: () {
                          setState(() {
                            _filterMenuIndex = index;
                            if (_filterMenuKind == _FilterMenuKind.system) {
                              _selectedSystemId = values[index] as String?;
                            } else {
                              _membershipFilter =
                                  values[index] as _MembershipFilter;
                            }
                          });
                          _closeFilterMenu(commit: true);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddGamesFooter extends CoreFooter {
  const _AddGamesFooter({
    required this.collectionName,
    required this.selectedCount,
    required this.onCancel,
    required this.onSave,
  });

  final String collectionName;
  final int selectedCount;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  bool get centerControls => false;

  @override
  bool get showVersion => false;

  @override
  Widget? buildLeftContent(BuildContext context) => Text(
    '$collectionName · $selectedCount ${AppLocale.selected.getString(context).toLowerCase()}',
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: 12.r,
      fontWeight: FontWeight.w600,
    ),
  );

  @override
  List<Widget> buildControls(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      GamepadControl(
        label: AppLocale.cancel.getString(context),
        iconPath: 'assets/images/gamepad/Xbox_B_button.png',
        onTap: onCancel,
        textColor: scheme.onSurface,
        backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        label: AppLocale.select.getString(context),
        iconPath: 'assets/images/gamepad/Xbox_A_button.png',
        textColor: scheme.onTertiaryFixed,
        backgroundColor: scheme.tertiaryFixed,
      ),
      SizedBox(width: 8.r),
      GamepadControl(
        label: AppLocale.save.getString(context),
        iconPath: 'assets/images/gamepad/Xbox_Y_button.png',
        onTap: onSave,
        textColor: scheme.onTertiary,
        backgroundColor: scheme.tertiary,
      ),
    ];
  }
}
