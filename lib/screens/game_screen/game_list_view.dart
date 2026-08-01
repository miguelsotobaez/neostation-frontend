import 'dart:io';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:neostation/services/sfx_service.dart';

import '../../services/game_service.dart';
import '../../themes/corner_radii.dart';
import '../../utils/centered_scroll_controller.dart';
import '../../utils/game_utils.dart';
import '../../providers/sqlite_config_provider.dart';
import '../../models/system_model.dart';
import '../../models/game_model.dart';
import '../../widgets/marquee_text.dart';
import '../../widgets/system_logo_fallback.dart';

/// A high-performance list view specialized for game browsing with gamepad support.
///
/// Features a centered scroll mechanism and smooth highlight animations
/// to emulate console-like library navigation.
class GameListView extends StatefulWidget {
  final SystemModel system;
  final List<GameModel> games;
  final int selectedIndex;
  final Color systemColor;
  final Function(GameModel) onGameSelected;

  /// Confirms the row that is already selected (same action as the A button).
  /// Tapping a row selects it; tapping the selected row again fires this.
  final VoidCallback onGameConfirmed;
  final bool isAllMode;
  final bool isNavigatingFast;
  final VoidCallback? onGamepadReactivated;

  const GameListView({
    super.key,
    required this.system,
    required this.games,
    required this.selectedIndex,
    required this.systemColor,
    required this.onGameSelected,
    required this.onGameConfirmed,
    this.isAllMode = false,
    this.isNavigatingFast = false,
    this.onGamepadReactivated,
  });

  @override
  State<GameListView> createState() => GameListViewState();
}

class GameListViewState extends State<GameListView>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final CenteredScrollController _centeredScrollController;
  late List<FocusNode> _gameFocusNodes;
  late AnimationController _selectionController;
  late Animation<double> _selectionAnimation;

  // Constants for pixel-perfect highlight positioning.
  static const double _itemHeightBase = 26.0;

  /// Public API to trigger list scrolling from the parent widget.
  void scrollToIndex(
    int index, {
    bool immediate = false,
    Duration? duration,
    Curve? curve,
  }) {
    _centeredScrollController.scrollToIndex(
      index,
      immediate: immediate,
      duration: duration,
      curve: curve,
    );
  }

  /// Immediately jumps to center on the item at [index] without animation.
  /// Unlike [scrollToIndex], this executes synchronously.
  void jumpToIndex(int index) {
    _centeredScrollController.jumpToIndex(index);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _centeredScrollController = CenteredScrollController(centerPosition: 0.5);

    _selectionController = AnimationController(
      duration: const Duration(milliseconds: 120),
      vsync: this,
    );
    _selectionAnimation = AlwaysStoppedAnimation(
      widget.selectedIndex.toDouble(),
    );

    _gameFocusNodes = List.generate(
      widget.games.length,
      (_) => FocusNode(skipTraversal: true),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _centeredScrollController.initialize(
          context: context,
          initialIndex: widget.selectedIndex,
          totalItems: widget.games.length,
        );
      }
    });
  }

  @override
  void didUpdateWidget(GameListView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.games.length != widget.games.length) {
      _centeredScrollController.updateTotalItems(widget.games.length);
      _updateFocusNodes();
    }

    if (oldWidget.selectedIndex != widget.selectedIndex) {
      // Dynamic duration adjustment based on navigation speed (isNavigatingFast).
      final animationDuration = widget.isNavigatingFast
          ? const Duration(milliseconds: 120)
          : const Duration(milliseconds: 250);

      final scrollDuration = widget.isNavigatingFast
          ? const Duration(milliseconds: 180)
          : const Duration(milliseconds: 360);

      const curve = Curves.easeOutQuart;

      final double begin = _selectionAnimation.value;
      final double end = widget.selectedIndex.toDouble();

      _selectionController.duration = animationDuration;
      _selectionAnimation = Tween<double>(
        begin: begin,
        end: end,
      ).animate(CurvedAnimation(parent: _selectionController, curve: curve));

      _selectionController.forward(from: 0);

      _centeredScrollController.updateSelectedIndex(widget.selectedIndex);
      _centeredScrollController.scrollToIndex(
        widget.selectedIndex,
        duration: scrollDuration,
        curve: curve,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _centeredScrollController.dispose();
    _selectionController.dispose();
    for (final node in _gameFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _updateFocusNodes() {
    final newCount = widget.games.length;
    if (newCount < _gameFocusNodes.length) {
      for (int i = newCount; i < _gameFocusNodes.length; i++) {
        _gameFocusNodes[i].dispose();
      }
      _gameFocusNodes.removeRange(newCount, _gameFocusNodes.length);
    } else {
      for (int i = _gameFocusNodes.length; i < newCount; i++) {
        _gameFocusNodes.add(FocusNode(skipTraversal: true));
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          // Suppress premature reactivation during external emulator handoff (Linux specific).
          if (!GameService.isGameLaunched) {
            widget.onGamepadReactivated?.call();
          }
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemHeight = _itemHeightBase.r;
    final totalItemHeight = itemHeight;
    _centeredScrollController.setItemExtent(totalItemHeight, paddingTop: 2.r);

    return Column(
      children: [
        _buildHeader(),

        Expanded(
          child: Stack(
            children: [
              // Highlight Layer: Dynamically follows the selected index with smooth interpolation.
              AnimatedBuilder(
                animation: Listenable.merge([
                  _selectionController,
                  _centeredScrollController.scrollController,
                ]),
                builder: (context, child) {
                  if (!_centeredScrollController.scrollController.hasClients) {
                    return const SizedBox.shrink();
                  }

                  final double scrollOffset =
                      _centeredScrollController.scrollController.offset;
                  final double currentSelection = _selectionAnimation.value;

                  // Absolute viewport positioning: (Index * ItemHeight) + Padding - ScrollOffset.
                  final double topPosition =
                      (currentSelection * totalItemHeight) + 2.r - scrollOffset;

                  final highlightColor = theme.colorScheme.primary;

                  return Positioned(
                    top: topPosition,
                    left: 8.r,
                    right: 8.r,
                    height: itemHeight,
                    child: RepaintBoundary(
                      child: Container(
                        decoration: BoxDecoration(
                          color: highlightColor,
                          borderRadius:
                              Theme.of(
                                context,
                              ).extension<CornerRadii>()?.radiusInternal ??
                              BorderRadius.circular(14.r),
                          boxShadow: [
                            BoxShadow(
                              color: Theme.of(
                                context,
                              ).colorScheme.shadow.withValues(alpha: 0.1),
                              blurRadius: 4.r,
                              offset: Offset(2.0.r, 2.0.r),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),

              // Foreground Content: The actual game list items.
              ValueListenableBuilder<int>(
                valueListenable: _centeredScrollController.rebuildNotifier,
                builder: (context, rebuildCount, _) {
                  return ListView.builder(
                    key: ValueKey('games_list_rebuild_$rebuildCount'),
                    controller: _centeredScrollController.scrollController,
                    padding: EdgeInsets.symmetric(
                      vertical: 2.r,
                      horizontal: 8.r,
                    ),
                    itemCount: widget.games.length,
                    itemBuilder: (context, index) {
                      final game = widget.games[index];
                      final isSelected = index == widget.selectedIndex;

                      return GestureDetector(
                        onTap: () {
                          // Touch users have no A button: the first tap selects
                          // the row (populating the details panel), a second tap
                          // on that same row launches it.
                          if (isSelected) {
                            SfxService().playEnterSound();
                            widget.onGameConfirmed();
                            return;
                          }
                          SfxService().playNavSound();
                          widget.onGameSelected(game);
                        },
                        child: Container(
                          height: totalItemHeight,
                          color: Colors.transparent,
                          child: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8.r,
                              vertical: 2.r,
                            ),
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                if (game.isFavorite == true)
                                  Container(
                                    margin: EdgeInsets.only(right: 4.r),
                                    child: Icon(
                                      Symbols.favorite_rounded,
                                      size: 11.r,
                                      color: isSelected
                                          ? theme.colorScheme.onPrimary
                                          : Colors.redAccent,
                                    ),
                                  ),
                                Expanded(
                                  child: RepaintBoundary(
                                    child: AnimatedDefaultTextStyle(
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      curve: Curves.easeOut,
                                      style: TextStyle(
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                        fontSize: 11.r,
                                        color: isSelected
                                            ? theme.colorScheme.onPrimary
                                            : theme.colorScheme.onSurface,
                                        fontFamily: theme
                                            .textTheme
                                            .bodyMedium
                                            ?.fontFamily,
                                      ),
                                      child: MarqueeText(
                                        text: GameUtils.formatGameName(
                                          game.name.isNotEmpty
                                              ? game.name
                                              : game.romname,
                                        ),
                                        isActive: isSelected,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// System Branding Header: Renders the system logo.
  Widget _buildHeader() {
    SystemModel displaySystem = widget.system;

    if (widget.isAllMode && widget.selectedIndex < widget.games.length) {
      final selectedGame = widget.games[widget.selectedIndex];
      final systemFolderName = selectedGame.systemFolderName;
      if (systemFolderName != null) {
        final availableSystems = context
            .read<SqliteConfigProvider>()
            .availableSystems;
        displaySystem = availableSystems.firstWhere(
          (sys) => sys.folderName == systemFolderName,
          orElse: () => widget.system,
        );
      }
    }

    return Container(
      margin: EdgeInsets.only(left: 8.r, right: 8.r, top: 8.r, bottom: 4.r),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSystemLogoHeader(displaySystem),
          SizedBox(height: 4.r),
        ],
      ),
    );
  }

  /// Renders the system brand logo with fallback support, tinted to match the theme.
  Widget _buildSystemLogoHeader(SystemModel displaySystem) {
    final resolvedLogoFolder = displaySystem.primaryFolderName.isNotEmpty
        ? displaySystem.primaryFolderName
        : (displaySystem.folderName.isNotEmpty
              ? displaySystem.folderName
              : 'all');
    final assetLogoPath = 'assets/images/logos/$resolvedLogoFolder.webp';
    final customLogoPath = displaySystem.customLogoPath;
    final hasCustomLogo = customLogoPath != null && customLogoPath.isNotEmpty;

    Widget buildLogo(Widget image) {
      return ColorFiltered(
        colorFilter: ColorFilter.mode(
          Theme.of(context).colorScheme.onSurface,
          BlendMode.srcIn,
        ),
        child: image,
      );
    }

    if (hasCustomLogo) {
      return buildLogo(
        Image.file(
          File(customLogoPath),
          height: 38.r,
          cacheWidth: 256,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Image.asset(
            assetLogoPath,
            height: 38.r,
            cacheWidth: 256,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => SystemLogoFallback(
              title: displaySystem.realName,
              shortName: displaySystem.shortName,
              height: 38.r,
            ),
          ),
        ),
      );
    }

    return buildLogo(
      Image.asset(
        assetLogoPath,
        height: 38.r,
        cacheWidth: 256,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => SystemLogoFallback(
          title: displaySystem.realName,
          shortName: displaySystem.shortName,
          height: 38.r,
        ),
      ),
    );
  }
}
