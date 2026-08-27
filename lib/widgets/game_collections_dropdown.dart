import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/providers/collection_provider.dart';
import 'package:neostation/repositories/collection_repository.dart';
import 'package:neostation/screens/collections_screen/create_edit_collection_dialog.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/game_utils.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:provider/provider.dart';

/// Dropdown dialog allowing users to quickly toggle a game's Favorite status
/// and membership across user-created Collections.
class GameCollectionsDropdown extends StatefulWidget {
  static final GlobalKey<GameCollectionsDropdownState> globalKey =
      GlobalKey<GameCollectionsDropdownState>();

  GameCollectionsDropdown() : super(key: globalKey);

  @override
  State<GameCollectionsDropdown> createState() =>
      GameCollectionsDropdownState();

  static Future<void> show({
    required BuildContext context,
    required GameModel game,
    VoidCallback? onFavoriteToggled,
    VoidCallback? onCollectionsUpdated,
    GlobalKey? anchorKey,
  }) async {
    Offset offset = Offset(12.r, 42.r);
    if (anchorKey?.currentContext != null) {
      final RenderBox? renderBox =
          anchorKey!.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final boxOffset = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        offset = boxOffset + Offset(0, size.height + 6.r);
      }
    }

    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Game Collections Dropdown",
      barrierColor: Colors.transparent,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: GameCollectionsOverlay(
            game: game,
            offset: offset,
            width: 230.r,
            onFavoriteToggled: onFavoriteToggled,
            onCollectionsUpdated: onCollectionsUpdated,
          ),
        );
      },
    );
  }
}

class GameCollectionsDropdownState extends State<GameCollectionsDropdown> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

enum _ItemType { favorite, collection, createCollection }

class _DropdownItem {
  final _ItemType type;
  final String label;
  final IconData icon;
  final Color? color;
  final bool isChecked;
  final CollectionModel? collection;

  const _DropdownItem({
    required this.type,
    required this.label,
    required this.icon,
    this.color,
    this.isChecked = false,
    this.collection,
  });
}

class GameCollectionsOverlay extends StatefulWidget {
  final GameModel game;
  final Offset offset;
  final double width;
  final VoidCallback? onFavoriteToggled;
  final VoidCallback? onCollectionsUpdated;

  const GameCollectionsOverlay({
    super.key,
    required this.game,
    required this.offset,
    required this.width,
    this.onFavoriteToggled,
    this.onCollectionsUpdated,
  });

  @override
  State<GameCollectionsOverlay> createState() => _GameCollectionsOverlayState();
}

class _GameCollectionsOverlayState extends State<GameCollectionsOverlay> {
  late GamepadNavigation _gamepadNav;
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();

  late bool _isFavorite;
  Set<int> _assignedCollectionIds = {};

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.game.isFavorite ?? false;
    _setupGamepad();
    _loadCollectionMemberships();
  }

  void _setupGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: () {
        final count = _buildItemsList().length;
        if (count == 0) return;
        setState(() {
          _selectedIndex = (_selectedIndex - 1 + count) % count;
        });
        _scrollToSelected();
        SfxService().playNavSound();
      },
      onNavigateDown: () {
        final count = _buildItemsList().length;
        if (count == 0) return;
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % count;
        });
        _scrollToSelected();
        SfxService().playNavSound();
      },
      onSelectItem: _handleSelection,
      onBack: () => Navigator.of(context).pop(),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'game_collections_overlay',
        modal: true,
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });
  }

  Future<void> _loadCollectionMemberships() async {
    final romPath = widget.game.romPath;
    if (romPath != null && romPath.isNotEmpty) {
      final ids = await CollectionRepository.getCollectionIdsForGame(romPath);
      if (mounted) {
        setState(() {
          _assignedCollectionIds = ids.toSet();
        });
      }
    }
  }

  void _scrollToSelected() {
    if (!mounted || !_scrollController.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final targetOffset = (_selectedIndex * 36.r).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeInOut,
      );
    });
  }

  Color? _parseHexColor(String? hex) {
    if (hex == null || hex.isEmpty) return null;
    final clean = hex.replaceAll('#', '');
    if (clean.length == 6) {
      return Color(int.parse('FF$clean', radix: 16));
    }
    return null;
  }

  List<_DropdownItem> _buildItemsList() {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final collections = context.read<CollectionProvider>().collections;

    final List<_DropdownItem> items = [
      _DropdownItem(
        type: _ItemType.favorite,
        label: AppLocale.favorite.getString(context),
        icon: _isFavorite
            ? Symbols.favorite_rounded
            : Symbols.favorite_border_rounded,
        color: _isFavorite ? Colors.redAccent : null,
        isChecked: _isFavorite,
      ),
      ...collections.map((col) {
        final isChecked = _assignedCollectionIds.contains(col.id);
        final colColor = _parseHexColor(col.color);
        return _DropdownItem(
          type: _ItemType.collection,
          label: col.name,
          icon: Symbols.collections_bookmark_rounded,
          color: isChecked ? (colColor ?? primaryColor) : null,
          isChecked: isChecked,
          collection: col,
        );
      }),
      _DropdownItem(
        type: _ItemType.createCollection,
        label: AppLocale.createCollection.getString(context),
        icon: Symbols.add_circle_outline_rounded,
        color: primaryColor,
        isChecked: false,
      ),
    ];

    return items;
  }

  Future<void> _handleSelection() async {
    final items = _buildItemsList();
    if (_selectedIndex < 0 || _selectedIndex >= items.length) return;

    final item = items[_selectedIndex];
    switch (item.type) {
      case _ItemType.favorite:
        setState(() => _isFavorite = !_isFavorite);
        await GameService.toggleFavorite(widget.game);
        widget.onFavoriteToggled?.call();
        SfxService().playEnterSound();
        break;

      case _ItemType.collection:
        if (item.collection == null || widget.game.romPath == null) return;
        final colId = item.collection!.id;
        final isCurrentlyIn = _assignedCollectionIds.contains(colId);

        setState(() {
          if (isCurrentlyIn) {
            _assignedCollectionIds.remove(colId);
          } else {
            _assignedCollectionIds.add(colId);
          }
        });

        if (isCurrentlyIn) {
          await CollectionRepository.removeGamesFromCollection(colId, [
            widget.game.romPath!,
          ]);
        } else {
          await CollectionRepository.addGamesToCollection(colId, [
            widget.game.romPath!,
          ]);
        }

        if (mounted) {
          context.read<CollectionProvider>().loadCollections(notify: false);
        }
        widget.onCollectionsUpdated?.call();
        SfxService().playEnterSound();
        break;

      case _ItemType.createCollection:
        Navigator.of(context).pop();
        CreateEditCollectionDialog.show(
          context: context,
          onSave: (result) async {
            final provider = context.read<CollectionProvider>();
            final created = await provider.createCollection(
              name: result.name,
              description: result.description,
            );
            if (created != null && widget.game.romPath != null) {
              await CollectionRepository.addGamesToCollection(created.id, [
                widget.game.romPath!,
              ]);
              await provider.loadCollections();
              widget.onCollectionsUpdated?.call();
            }
          },
        );
        break;
    }
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('game_collections_overlay');
    _gamepadNav.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final items = _buildItemsList();

    return Stack(
      children: [
        Positioned(
          top: widget.offset.dy.clamp(10.r, 1080.r - 320.r),
          left: widget.offset.dx.clamp(6.r, 1920.r - widget.width - 6.r),
          width: widget.width,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: EdgeInsets.symmetric(vertical: 8.r),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: primaryColor.withValues(alpha: 0.25),
                  width: 1.r,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 15.r,
                    offset: Offset(0, 5.r),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.r),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Header with game name
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.r,
                        vertical: 4.r,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Symbols.bookmarks_rounded,
                            size: 16.r,
                            color: primaryColor,
                          ),
                          SizedBox(width: 6.r),
                          Expanded(
                            child: Text(
                              GameUtils.formatGameName(widget.game.name),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.r,
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 8.r,
                      thickness: 1.r,
                      color: theme.colorScheme.outline.withValues(alpha: 0.15),
                    ),

                    // Scrollable Options List
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: 280.r),
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        physics: const BouncingScrollPhysics(),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (int i = 0; i < items.length; i++)
                              _buildOptionRow(
                                item: items[i],
                                isFocused: i == _selectedIndex,
                                index: i,
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
      ],
    );
  }

  Widget _buildOptionRow({
    required _DropdownItem item,
    required bool isFocused,
    required int index,
  }) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    final isCreate = item.type == _ItemType.createCollection;
    final isFavorite = item.type == _ItemType.favorite;

    return InkWell(
      onTap: () {
        setState(() => _selectedIndex = index);
        _handleSelection();
      },
      focusColor: Colors.transparent,
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.r, vertical: 7.r),
        decoration: BoxDecoration(
          color: isFocused
              ? primaryColor.withValues(alpha: 0.18)
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isFocused ? primaryColor : Colors.transparent,
              width: 3.r,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 16.r,
              color:
                  item.color ??
                  (isFocused
                      ? primaryColor
                      : theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            ),
            SizedBox(width: 10.r),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.r,
                  fontWeight: isFocused || item.isChecked
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: isFocused
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ),
            if (!isCreate) ...[
              SizedBox(width: 8.r),
              Icon(
                item.isChecked
                    ? (isFavorite
                          ? Symbols.favorite_rounded
                          : Symbols.check_box_rounded)
                    : (isFavorite
                          ? Symbols.favorite_border_rounded
                          : Symbols.check_box_outline_blank_rounded),
                size: 16.r,
                color: item.isChecked
                    ? (item.color ?? primaryColor)
                    : theme.colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
