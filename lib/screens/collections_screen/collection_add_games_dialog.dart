import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/repositories/system_repository.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';

/// Which band currently holds gamepad focus.
enum _FocusBand { search, filters, results }

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
  final ScrollController _chipScrollController = ScrollController();
  late final GamepadNavigation _gamepadNav;

  final Map<int, GlobalKey> _chipKeys = {};

  List<GameModel> _allGames = [];
  List<SystemModel> _systems = [];
  late Set<String> _selectedRomPaths;

  String _searchQuery = '';
  String? _selectedSystemId; // null = all systems
  bool _isLoading = true;

  _FocusBand _focusBand = _FocusBand.results;
  int _focusedFilterIndex = 0;
  int _focusedGameIndex = 0;

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
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _selectedRomPaths = Set<String>.from(widget.initialSelectedRomPaths);
    _loadData();
    _setupGamepad();
  }

  Future<void> _loadData() async {
    try {
      final dbGames = await SqliteService.getAllGames();
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
      onPreviousTab: _handlePageUp,
      onNextTab: _handlePageDown,
      isTextFieldFocused: () => _searchFocusNode.hasFocus,
    );
    _gamepadNav.initialize();

    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    _chipScrollController.dispose();
    super.dispose();
  }

  void _handleNavigateUp() {
    if (_focusBand == _FocusBand.results) {
      if (_focusedGameIndex > 0) {
        SfxService().playNavSound();
        setState(() => _focusedGameIndex--);
        _scrollToFocusedGame();
      } else {
        // Move up to filter chips
        SfxService().playNavSound();
        setState(() => _focusBand = _FocusBand.filters);
        _scrollChipIntoView();
      }
    } else if (_focusBand == _FocusBand.filters) {
      // Move up to search bar
      SfxService().playNavSound();
      setState(() => _focusBand = _FocusBand.search);
    }
  }

  void _handleNavigateDown() {
    if (_focusBand == _FocusBand.search) {
      SfxService().playNavSound();
      _searchFocusNode.unfocus();
      setState(() => _focusBand = _FocusBand.filters);
      _scrollChipIntoView();
    } else if (_focusBand == _FocusBand.filters) {
      if (_filteredGames.isNotEmpty) {
        SfxService().playNavSound();
        setState(() {
          _focusBand = _FocusBand.results;
          _focusedGameIndex = 0;
        });
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
    if (_focusBand == _FocusBand.filters) {
      if (_focusedFilterIndex > 0) {
        SfxService().playNavSound();
        setState(() => _focusedFilterIndex--);
        _scrollChipIntoView();
      }
    } else if (_focusBand == _FocusBand.results) {
      _handlePageUp();
    }
  }

  void _handleNavigateRight() {
    final totalChips = _systems.length + 1; // +1 for All Systems
    if (_focusBand == _FocusBand.filters) {
      if (_focusedFilterIndex < totalChips - 1) {
        SfxService().playNavSound();
        setState(() => _focusedFilterIndex++);
        _scrollChipIntoView();
      }
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
    if (_focusBand == _FocusBand.search) {
      _searchFocusNode.requestFocus();
    } else if (_focusBand == _FocusBand.filters) {
      SfxService().playEnterSound();
      if (_focusedFilterIndex == 0) {
        setState(() {
          _selectedSystemId = null;
          _focusedGameIndex = 0;
        });
      } else {
        final sys = _systems[_focusedFilterIndex - 1];
        setState(() {
          _selectedSystemId = sys.folderName;
          _focusedGameIndex = 0;
        });
      }
    } else if (_focusBand == _FocusBand.results) {
      _toggleFocusedGame();
    }
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

  void _scrollChipIntoView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final chipContext = _chipKeys[_focusedFilterIndex]?.currentContext;
      if (chipContext == null) return;
      Scrollable.ensureVisible(
        chipContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
      );
    });
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
    _finishAndSave();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final filtered = _filteredGames;

    return Dialog.fullscreen(
      backgroundColor: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Column(
          children: [
            // Top App Bar
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
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
                  IconButton(
                    icon: const Icon(Symbols.arrow_back_rounded),
                    onPressed: _finishAndSave,
                  ),
                  SizedBox(width: 8.w),
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
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 14.w,
                      vertical: 6.h,
                    ),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20.r),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '${_selectedRomPaths.length} selected',
                      style: TextStyle(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: 16.w,
                        vertical: 10.h,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                    ),
                    icon: const Icon(Symbols.check_rounded),
                    label: const Text('Done [B]'),
                    onPressed: _finishAndSave,
                  ),
                ],
              ),
            ),

            // Search Bar & System Filters Row
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
              child: Column(
                children: [
                  // Search Input
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
                          width: (_focusBand == _FocusBand.search) ? 2.r : 1.r,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12.r),
                        borderSide: BorderSide(
                          color: (_focusBand == _FocusBand.search)
                              ? primaryColor
                              : theme.dividerColor.withValues(alpha: 0.2),
                          width: (_focusBand == _FocusBand.search) ? 2.r : 1.r,
                        ),
                      ),
                    ),
                    onChanged: (val) {
                      setState(() {
                        _searchQuery = val.trim();
                        _focusedGameIndex = 0;
                      });
                    },
                    onSubmitted: (_) => _searchFocusNode.unfocus(),
                  ),
                  SizedBox(height: 10.h),

                  // System Filter Chips Horizontal Scroll
                  SizedBox(
                    height: 36.h,
                    child: ListView(
                      controller: _chipScrollController,
                      scrollDirection: Axis.horizontal,
                      children: [
                        KeyedSubtree(
                          key: _chipKeys.putIfAbsent(0, () => GlobalKey()),
                          child: _buildFilterChip(
                            label: AppLocale.allSystems.getString(context),
                            isSelected: _selectedSystemId == null,
                            isFocused:
                                _focusBand == _FocusBand.filters &&
                                _focusedFilterIndex == 0,
                            onTap: () {
                              SfxService().playNavSound();
                              setState(() {
                                _selectedSystemId = null;
                                _focusedFilterIndex = 0;
                                _focusedGameIndex = 0;
                              });
                            },
                          ),
                        ),
                        ..._systems.asMap().entries.map((entry) {
                          final idx = entry.key + 1;
                          final sys = entry.value;
                          return KeyedSubtree(
                            key: _chipKeys.putIfAbsent(idx, () => GlobalKey()),
                            child: _buildFilterChip(
                              label: sys.realName,
                              isSelected: _selectedSystemId == sys.folderName,
                              isFocused:
                                  _focusBand == _FocusBand.filters &&
                                  _focusedFilterIndex == idx,
                              onTap: () {
                                SfxService().playNavSound();
                                setState(() {
                                  _selectedSystemId = sys.folderName;
                                  _focusedFilterIndex = idx;
                                  _focusedGameIndex = 0;
                                });
                              },
                            ),
                          );
                        }),
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
                        final isSelected = _selectedRomPaths.contains(romPath);
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
                                          ? primaryColor.withValues(alpha: 0.08)
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
                                            fontWeight: isSelected || isFocused
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
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required bool isFocused,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: EdgeInsets.only(right: 8.w),
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          decoration: BoxDecoration(
            color: isSelected
                ? primaryColor
                : (isFocused
                      ? primaryColor.withValues(alpha: 0.2)
                      : theme.cardColor.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: isFocused
                  ? (isSelected ? Colors.white : primaryColor)
                  : (isSelected
                        ? primaryColor
                        : theme.dividerColor.withValues(alpha: 0.3)),
              width: isFocused ? 2.r : 1.r,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: isSelected || isFocused
                  ? FontWeight.bold
                  : FontWeight.normal,
              color: isSelected
                  ? Colors.white
                  : (isFocused
                        ? primaryColor
                        : theme.textTheme.bodyMedium?.color),
            ),
          ),
        ),
      ),
    );
  }
}
