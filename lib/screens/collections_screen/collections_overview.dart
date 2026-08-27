import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/models/my_systems.dart';
import 'package:neostation/providers/collection_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/responsive.dart';
import 'package:neostation/screens/systems_screen/my_systems_section/my_systems_grid.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/widgets/confirm_action_dialog.dart';
import 'package:neostation/widgets/systems_grid_footer.dart';
import 'package:provider/provider.dart';

import '../../repositories/collection_repository.dart';
import 'collection_add_games_dialog.dart';
import 'create_edit_collection_dialog.dart';

/// Overview grid displaying all collections and the "+ Create Collection" card
/// using the identical [SystemCardGridView] and [SystemsGridFooter] platform UI components.
class CollectionsOverview extends StatefulWidget {
  final ValueChanged<CollectionModel> onSelectCollection;

  const CollectionsOverview({super.key, required this.onSelectCollection});

  @override
  State<CollectionsOverview> createState() => _CollectionsOverviewState();
}

class _CollectionsOverviewState extends State<CollectionsOverview> {
  int _selectedIndex = 0;

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
          setState(() => _selectedIndex = provider.collections.length - 1);
        }
      },
    );
  }

  void _showOptionsFor(CollectionModel col) {
    final provider = context.read<CollectionProvider>();
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
      if (_selectedIndex > 0 && _selectedIndex >= provider.collections.length) {
        setState(() => _selectedIndex = provider.collections.length - 1);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<CollectionProvider, SqliteConfigProvider>(
      builder: (context, collectionProvider, configProvider, child) {
        if (collectionProvider.isLoading &&
            collectionProvider.collections.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        final collections = collectionProvider.collections;
        final theme = Theme.of(context);
        final primaryColor = theme.colorScheme.primary;

        final List<SystemInfo> systemCards = [
          ...collections.map(
            (col) => SystemInfo.fromSystemModel(col.toSystemModel()),
          ),
          SystemInfo(
            title: AppLocale.createCollection.getString(context),
            shortName: AppLocale.createCollection.getString(context),
            numOfRoms: 0,
            color: primaryColor,
            color1:
                '#${primaryColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}',
            color2: '#1A1A2E',
            folderName: 'create_collection',
            primaryFolderName: 'create_collection',
            hideLogo: false,
            isGame: false,
          ),
        ];

        final safeIndex = _selectedIndex.clamp(0, systemCards.length - 1);
        final currentSystem = systemCards[safeIndex];

        return Column(
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 6.0.r,
                  right: 6.0.r,
                  top: 46.r,
                  bottom: 0.r,
                ),
                child: SystemCardGridView(
                  crossAxisCount: Responsive.getSystemsCrossAxisCountFromSize(
                    configProvider.config.systemGridColumns,
                  ),
                  childAspectRatio: 0.80,
                  selectedIndex: safeIndex,
                  layerName: 'collections_grid',
                  onCardTapped: (index) {
                    setState(() => _selectedIndex = index);
                  },
                  systems: systemCards,
                  onEnterPressed: () {
                    if (safeIndex < collections.length) {
                      final col = collections[safeIndex];
                      SfxService().playEnterSound();
                      widget.onSelectCollection(col);
                    } else {
                      _openCreateDialog();
                    }
                  },
                  onEscapePressed: () {
                    if (safeIndex < collections.length) {
                      _showOptionsFor(collections[safeIndex]);
                    }
                  },
                  onXPressed: _openCreateDialog,
                ),
              ),
            ),
            SystemsGridFooter(
              system: currentSystem,
              onEnter: () {
                if (safeIndex < collections.length) {
                  final col = collections[safeIndex];
                  SfxService().playEnterSound();
                  widget.onSelectCollection(col);
                } else {
                  _openCreateDialog();
                }
              },
              onSettings: safeIndex < collections.length
                  ? () {
                      SfxService().playEnterSound();
                      _showOptionsFor(collections[safeIndex]);
                    }
                  : null,
              onExtra: _openCreateDialog,
              extraLabel:
                  '${AppLocale.createCollection.getString(context)} [X]',
            ),
          ],
        );
      },
    );
  }
}
