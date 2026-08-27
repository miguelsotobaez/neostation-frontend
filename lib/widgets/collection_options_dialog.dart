import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/providers/collection_provider.dart';
import 'package:neostation/repositories/collection_repository.dart';
import 'package:neostation/screens/collections_screen/collection_add_games_dialog.dart';
import 'package:neostation/screens/collections_screen/create_edit_collection_dialog.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/widgets/confirm_action_dialog.dart';
import 'package:provider/provider.dart';

enum CollectionAction { addGames, editDetails, delete }

/// Styled dropdown menu matching [GameViewModeDropdown] and [GameCollectionsDropdown]
/// allowing users to manage games, edit details, or delete a collection.
class CollectionOptionsDropdown extends StatefulWidget {
  const CollectionOptionsDropdown({super.key});

  static Future<void> show({
    required BuildContext context,
    required CollectionModel collection,
    GlobalKey? anchorKey,
    VoidCallback? onCollectionUpdated,
    VoidCallback? onCollectionDeleted,
  }) async {
    Offset offset = Offset(1920.r / 2 - 120.r, 1080.r / 2 - 100.r);
    if (anchorKey?.currentContext != null) {
      final RenderBox? renderBox =
          anchorKey!.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final boxOffset = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        offset = boxOffset + Offset(0, size.height + 6.r);
      }
    }

    final action = await showGeneralDialog<CollectionAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: "Collection Options Dropdown",
      barrierColor: Colors.black26,
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: _CollectionOptionsOverlay(
            collection: collection,
            offset: offset,
            width: 240.r,
          ),
        );
      },
    );

    if (action == null || !context.mounted) return;

    final provider = context.read<CollectionProvider>();

    switch (action) {
      case CollectionAction.addGames:
        final existingGames = await CollectionRepository.getGamesForCollection(
          collection.id,
        );
        final existingPaths = existingGames.map((g) => g.romPath).toSet();
        if (!context.mounted) return;
        await CollectionAddGamesDialog.show(
          context: context,
          collectionName: collection.name,
          initialSelectedRomPaths: existingPaths,
          onSave: (newPaths) async {
            await provider.setGamesForCollection(
              collection.id,
              newPaths.toList(),
            );
            await provider.loadCollections();
            onCollectionUpdated?.call();
          },
        );
        break;

      case CollectionAction.editDetails:
        if (!context.mounted) return;
        CreateEditCollectionDialog.show(
          context: context,
          collection: collection,
          onSave: (res) async {
            await provider.updateCollection(
              collection.id,
              name: res.name,
              description: res.description,
            );
            await provider.loadCollections();
            onCollectionUpdated?.call();
          },
        );
        break;

      case CollectionAction.delete:
        if (!context.mounted) return;
        final confirmed = await ConfirmActionDialog.show(
          context,
          title: AppLocale.deleteCollection.getString(context),
          body: AppLocale.deleteCollectionConfirm.getString(context),
          confirmLabel: 'Delete',
          icon: Symbols.delete_forever_rounded,
        );
        if (confirmed && context.mounted) {
          await provider.deleteCollection(collection.id);
          onCollectionDeleted?.call();
        }
        break;
    }
  }

  @override
  State<CollectionOptionsDropdown> createState() =>
      _CollectionOptionsDropdownState();
}

class _CollectionOptionsDropdownState extends State<CollectionOptionsDropdown> {
  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

class _OptionItem {
  final CollectionAction action;
  final String label;
  final IconData icon;
  final Color? color;
  final bool isDestructive;

  const _OptionItem({
    required this.action,
    required this.label,
    required this.icon,
    this.color,
    this.isDestructive = false,
  });
}

class _CollectionOptionsOverlay extends StatefulWidget {
  final CollectionModel collection;
  final Offset offset;
  final double width;

  const _CollectionOptionsOverlay({
    required this.collection,
    required this.offset,
    required this.width,
  });

  @override
  State<_CollectionOptionsOverlay> createState() =>
      _CollectionOptionsOverlayState();
}

class _CollectionOptionsOverlayState extends State<_CollectionOptionsOverlay> {
  late GamepadNavigation _gamepadNav;
  int _selectedIndex = 0;
  final ScrollController _scrollController = ScrollController();

  List<_OptionItem> _getItems(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return [
      _OptionItem(
        action: CollectionAction.addGames,
        label: AppLocale.addGames.getString(context),
        icon: Symbols.checklist_rounded,
        color: primaryColor,
      ),
      _OptionItem(
        action: CollectionAction.editDetails,
        label: AppLocale.editCollection.getString(context),
        icon: Symbols.edit_rounded,
        color: primaryColor,
      ),
      _OptionItem(
        action: CollectionAction.delete,
        label: AppLocale.deleteCollection.getString(context),
        icon: Symbols.delete_forever_rounded,
        color: Colors.redAccent,
        isDestructive: true,
      ),
    ];
  }

  @override
  void initState() {
    super.initState();
    _setupGamepad();
  }

  void _setupGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: () {
        final count = _getItems(context).length;
        setState(() {
          _selectedIndex = (_selectedIndex - 1 + count) % count;
        });
        SfxService().playNavSound();
      },
      onNavigateDown: () {
        final count = _getItems(context).length;
        setState(() {
          _selectedIndex = (_selectedIndex + 1) % count;
        });
        SfxService().playNavSound();
      },
      onSelectItem: _handleSelection,
      onBack: () => Navigator.of(context).pop(),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'collection_options_overlay',
        modal: true,
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });
  }

  void _handleSelection() {
    final items = _getItems(context);
    if (_selectedIndex < 0 || _selectedIndex >= items.length) return;

    final item = items[_selectedIndex];
    Navigator.of(context).pop(item.action);
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('collection_options_overlay');
    _gamepadNav.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
    final items = _getItems(context);

    return Stack(
      children: [
        Positioned(
          top: widget.offset.dy.clamp(20.r, 1080.r - 260.r),
          left: widget.offset.dx.clamp(10.r, 1920.r - widget.width - 10.r),
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
                    // Header
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 14.r,
                        vertical: 4.r,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Symbols.collections_bookmark_rounded,
                            size: 16.r,
                            color: primaryColor,
                          ),
                          SizedBox(width: 8.r),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.collection.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.r,
                                    fontWeight: FontWeight.bold,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  '${widget.collection.romCount} ${AppLocale.games.getString(context).toLowerCase()}',
                                  style: TextStyle(
                                    fontSize: 10.r,
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                              ],
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

                    // Options List
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
          ),
        ),
      ],
    );
  }

  Widget _buildOptionRow({
    required _OptionItem item,
    required bool isFocused,
    required int index,
  }) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

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
        padding: EdgeInsets.symmetric(horizontal: 14.r, vertical: 8.r),
        decoration: BoxDecoration(
          color: isFocused
              ? (item.isDestructive
                    ? Colors.redAccent.withValues(alpha: 0.18)
                    : primaryColor.withValues(alpha: 0.18))
              : Colors.transparent,
          border: Border(
            left: BorderSide(
              color: isFocused
                  ? (item.isDestructive ? Colors.redAccent : primaryColor)
                  : Colors.transparent,
              width: 3.r,
            ),
          ),
        ),
        child: Row(
          children: [
            Icon(
              item.icon,
              size: 16.r,
              color: isFocused
                  ? (item.isDestructive ? Colors.redAccent : primaryColor)
                  : (item.color ??
                        theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            ),
            SizedBox(width: 10.r),
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.r,
                  fontWeight: isFocused ? FontWeight.w700 : FontWeight.w500,
                  color: isFocused
                      ? (item.isDestructive
                            ? Colors.redAccent
                            : theme.colorScheme.onSurface)
                      : (item.isDestructive
                            ? Colors.redAccent.withValues(alpha: 0.8)
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.85,
                              )),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
