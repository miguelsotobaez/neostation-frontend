import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/providers/collection_provider.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/widgets/confirm_action_dialog.dart';
import 'package:provider/provider.dart';

import '../../repositories/collection_repository.dart';
import '../app_screen.dart';
import 'collection_add_games_dialog.dart';
import 'collection_card.dart';
import 'create_edit_collection_dialog.dart';

/// Overview grid displaying all collections and the "+ Create Collection" card.
class CollectionsOverview extends StatefulWidget {
  final ValueChanged<CollectionModel> onSelectCollection;

  const CollectionsOverview({super.key, required this.onSelectCollection});

  @override
  State<CollectionsOverview> createState() => _CollectionsOverviewState();
}

class _CollectionsOverviewState extends State<CollectionsOverview> {
  int _focusedIndex = 0;
  static const int _crossAxisCount = 3;
  late final GamepadNavigation _gamepadNav;

  @override
  void initState() {
    super.initState();
    _setupGamepad();
  }

  void _setupGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateLeft: () => _moveFocus(-1),
      onNavigateRight: () => _moveFocus(1),
      onNavigateUp: () => _moveFocus(-_crossAxisCount),
      onNavigateDown: () => _moveFocus(_crossAxisCount),
      onSelectItem: _handleSelect,
      onXButton: _openCreateDialog,
      onFavorite: _showOptionsForFocused,
      onPreviousTab: AppNavigation.previousTab,
      onNextTab: AppNavigation.nextTab,
    );
    _gamepadNav.initialize();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      GamepadNavigationManager.pushLayer(
        'collections_overview',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });
  }

  @override
  void dispose() {
    _gamepadNav.dispose();
    GamepadNavigationManager.popLayer('collections_overview');
    super.dispose();
  }

  int _totalItems(int collectionCount) =>
      collectionCount + 1; // +1 for create card

  void _moveFocus(int delta) {
    final provider = context.read<CollectionProvider>();
    final total = _totalItems(provider.collections.length);
    final target = _focusedIndex + delta;

    if (target >= 0 && target < total) {
      SfxService().playNavSound();
      setState(() => _focusedIndex = target);
    }
  }

  void _handleSelect() {
    final provider = context.read<CollectionProvider>();
    if (_focusedIndex < provider.collections.length) {
      final col = provider.collections[_focusedIndex];
      SfxService().playEnterSound();
      widget.onSelectCollection(col);
    } else {
      // On "+" card
      _openCreateDialog();
    }
  }

  void _openCreateDialog() {
    final provider = context.read<CollectionProvider>();
    CreateEditCollectionDialog.show(
      context: context,
      onSave: (result) async {
        final created = await provider.createCollection(
          name: result.name,
          description: result.description,
        );
        if (created != null && mounted) {
          setState(() => _focusedIndex = provider.collections.length - 1);
        }
      },
    );
  }

  void _showOptionsForFocused() {
    final provider = context.read<CollectionProvider>();
    if (_focusedIndex >= provider.collections.length) return;

    final col = provider.collections[_focusedIndex];
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  col.name,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16.h),
                ListTile(
                  leading: Icon(Symbols.checklist_rounded, color: primaryColor),
                  title: Text(AppLocale.addGames.getString(context)),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final existingGames =
                        await CollectionRepository.getGamesForCollection(
                          col.id,
                        );
                    final existingPaths = existingGames
                        .map((g) => g.romPath)
                        .toSet();
                    if (!mounted) return;
                    await CollectionAddGamesDialog.show(
                      context: context,
                      collectionName: col.name,
                      initialSelectedRomPaths: existingPaths,
                      onSave: (newPaths) async {
                        await provider.setGamesForCollection(
                          col.id,
                          newPaths.toList(),
                        );
                        await provider.loadCollections();
                      },
                    );
                  },
                ),
                ListTile(
                  leading: Icon(Symbols.edit_rounded, color: primaryColor),
                  title: Text(AppLocale.editCollection.getString(context)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    CreateEditCollectionDialog.show(
                      context: context,
                      collection: col,
                      onSave: (res) async {
                        await provider.updateCollection(
                          col.id,
                          name: res.name,
                          description: res.description,
                        );
                      },
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Symbols.delete_forever_rounded,
                    color: Colors.redAccent,
                  ),
                  title: Text(
                    AppLocale.deleteCollection.getString(context),
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _deleteCollection(col);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteCollection(CollectionModel col) async {
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: AppLocale.deleteCollection.getString(context),
      body: AppLocale.deleteCollectionConfirm.getString(context),
      confirmLabel: 'Delete',
      icon: Symbols.delete_forever_rounded,
    );

    if (confirmed && mounted) {
      final provider = context.read<CollectionProvider>();
      await provider.deleteCollection(col.id);
      if (_focusedIndex > 0 && _focusedIndex >= provider.collections.length) {
        setState(() => _focusedIndex = provider.collections.length - 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Consumer<CollectionProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final collections = provider.collections;

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 16.h),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(
                        Symbols.collections_bookmark_rounded,
                        color: primaryColor,
                        size: 26.r,
                      ),
                      SizedBox(width: 10.w),
                      Text(
                        AppLocale.collections.getString(context),
                        style: TextStyle(
                          fontSize: 22.sp,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: 16.w,
                        vertical: 10.h,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    icon: Icon(Symbols.add_rounded, size: 20.r),
                    label: const Text('Create Collection [X]'),
                    onPressed: _openCreateDialog,
                  ),
                ],
              ),
              SizedBox(height: 20.h),

              // Collections Grid
              Expanded(
                child: GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: _crossAxisCount,
                    crossAxisSpacing: 18.w,
                    mainAxisSpacing: 18.h,
                    childAspectRatio: 1.45,
                  ),
                  itemCount: collections.length + 1,
                  itemBuilder: (context, index) {
                    if (index < collections.length) {
                      final col = collections[index];
                      return CollectionCard(
                        collection: col,
                        isFocused: index == _focusedIndex,
                        onTap: () {
                          setState(() => _focusedIndex = index);
                          _handleSelect();
                        },
                        onOptions: () {
                          setState(() => _focusedIndex = index);
                          _showOptionsForFocused();
                        },
                      );
                    } else {
                      // "+ Create Collection" Card
                      return CollectionCard(
                        isCreateCard: true,
                        isFocused: index == _focusedIndex,
                        onTap: () {
                          setState(() => _focusedIndex = index);
                          _openCreateDialog();
                        },
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
