import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/models/my_systems.dart';
import 'package:neostation/providers/collection_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/responsive.dart';
import 'package:neostation/screens/systems_screen/my_systems_section/my_systems_grid.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/widgets/systems_grid_footer.dart';
import 'package:provider/provider.dart';

import 'create_edit_collection_dialog.dart';
import '../../widgets/collection_options_dialog.dart';

/// Overview grid displaying all user collections using the identical
/// [SystemCardGridView] and [SystemsGridFooter] platform UI components.
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
    CollectionOptionsDropdown.show(
      context: context,
      collection: col,
      onCollectionUpdated: () {
        if (mounted) setState(() {});
      },
      onCollectionDeleted: () {
        if (mounted) {
          final provider = context.read<CollectionProvider>();
          if (_selectedIndex > 0 &&
              _selectedIndex >= provider.collections.length) {
            setState(() => _selectedIndex = provider.collections.length - 1);
          }
        }
      },
    );
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

        // If collections exist, only show user collections.
        // If 0 collections exist, show the single create collection card.
        final List<SystemInfo> systemCards = collections.isEmpty
            ? [
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
              ]
            : collections
                  .map((col) => SystemInfo.fromSystemModel(col.toSystemModel()))
                  .toList();

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
                    if (collections.isNotEmpty &&
                        safeIndex < collections.length) {
                      final col = collections[safeIndex];
                      SfxService().playEnterSound();
                      widget.onSelectCollection(col);
                    } else {
                      _openCreateDialog();
                    }
                  },
                  onEscapePressed: () {
                    if (collections.isNotEmpty &&
                        safeIndex < collections.length) {
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
                if (collections.isNotEmpty && safeIndex < collections.length) {
                  final col = collections[safeIndex];
                  SfxService().playEnterSound();
                  widget.onSelectCollection(col);
                } else {
                  _openCreateDialog();
                }
              },
              onSettings:
                  collections.isNotEmpty && safeIndex < collections.length
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
