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
import 'package:neostation/widgets/collection_options_dialog.dart';
import 'package:neostation/widgets/systems_grid_footer.dart';
import 'package:provider/provider.dart';

import 'create_edit_collection_dialog.dart';

/// Overview grid displaying all collections using the identical
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
      onSave: (newName) async {
        final created = await provider.createCollection(name: newName);
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

        if (collections.isEmpty) {
          return Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 32.r),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Symbols.collections_bookmark_rounded,
                    size: 64.r,
                    color: primaryColor.withValues(alpha: 0.5),
                  ),
                  SizedBox(height: 16.r),
                  Text(
                    AppLocale.noCollectionsTitle.getString(context),
                    style: TextStyle(
                      fontSize: 18.r,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 8.r),
                  Text(
                    AppLocale.noCollectionsSubtitle.getString(context),
                    style: TextStyle(
                      fontSize: 13.r,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24.r),
                  ElevatedButton.icon(
                    onPressed: _openCreateDialog,
                    icon: const Icon(Symbols.add_rounded),
                    label: Text(AppLocale.createCollection.getString(context)),
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: 24.r,
                        vertical: 12.r,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final List<SystemInfo> systemCards = collections
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
                    if (safeIndex < collections.length) {
                      final col = collections[safeIndex];
                      SfxService().playEnterSound();
                      widget.onSelectCollection(col);
                    }
                  },
                  onEscapePressed: () {
                    if (safeIndex < collections.length) {
                      _showOptionsFor(collections[safeIndex]);
                    }
                  },
                  onXPressed: () {
                    if (safeIndex < collections.length) {
                      _showOptionsFor(collections[safeIndex]);
                    }
                  },
                  onYPressed: () {
                    if (safeIndex < collections.length) {
                      _showOptionsFor(collections[safeIndex]);
                    }
                  },
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
                }
              },
              onSettings: () {
                SfxService().playEnterSound();
                _showOptionsFor(collections[safeIndex]);
              },
              settingsLabel: AppLocale.manage.getString(context),
            ),
          ],
        );
      },
    );
  }
}
