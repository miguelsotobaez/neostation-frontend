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
import 'package:neostation/screens/app_screen.dart';
import 'package:neostation/screens/systems_screen/my_systems_section/my_systems_grid.dart';
import 'package:neostation/screens/systems_screen/my_systems_section/system_card.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/widgets/collection_options_dialog.dart';
import 'package:neostation/widgets/header_sort_dropdown.dart';
import 'package:neostation/widgets/native_carousel.dart';
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
  int? _selectedCollectionId;

  List<CollectionModel> _sortedCollections(
    List<CollectionModel> source,
    SqliteConfigProvider configProvider,
  ) {
    final collections = [...source];
    final sortBy = configProvider.config.systemSortBy;
    final descending = configProvider.config.systemSortOrder == 'desc';
    int compare(CollectionModel a, CollectionModel b) {
      final result = switch (sortBy) {
        'year' =>
          (a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
            b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0),
          ),
        // Collections have no manufacturer/type metadata. Keep those shared
        // menu choices deterministic rather than applying system data to them.
        'manufacturer' || 'manufacturer_type' => a.name.toLowerCase().compareTo(
          b.name.toLowerCase(),
        ),
        _ => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      };
      return descending ? -result : result;
    }

    collections.sort(compare);
    return collections;
  }

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

        final collections = _sortedCollections(
          collectionProvider.collections,
          configProvider,
        );
        if (collections.isEmpty) {
          return _EmptyCollectionsView(onCreate: _openCreateDialog);
        }

        final List<SystemInfo> systemCards = collections
            .map((col) => SystemInfo.fromSystemModel(col.toSystemModel()))
            .toList();

        final selectedById = _selectedCollectionId == null
            ? -1
            : collections.indexWhere(
                (collection) => collection.id == _selectedCollectionId,
              );
        final safeIndex = (selectedById >= 0 ? selectedById : _selectedIndex)
            .clamp(0, systemCards.length - 1);
        final currentSystem = systemCards[safeIndex];

        void selectIndex(int index) {
          if (index < 0 || index >= collections.length) return;
          setState(() {
            _selectedIndex = index;
            _selectedCollectionId = collections[index].id;
          });
        }

        if (configProvider.config.systemViewMode == 'carousel') {
          return _CollectionsCarousel(
            collections: collections,
            selectedIndex: safeIndex,
            onSelected: selectIndex,
            onEnter: (index) => widget.onSelectCollection(collections[index]),
            onManage: (index) => _showOptionsFor(collections[index]),
            onCreate: _openCreateDialog,
          );
        }

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
                    selectIndex(index);
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
                  onYPressed: () {
                    _openCreateDialog();
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
              onExtra: _openCreateDialog,
              extraLabel: AppLocale.createCollection.getString(context),
              extraIconPath: 'assets/images/gamepad/Xbox_Y_button.png',
            ),
          ],
        );
      },
    );
  }
}

class _EmptyCollectionsView extends StatefulWidget {
  const _EmptyCollectionsView({required this.onCreate});

  final VoidCallback onCreate;

  @override
  State<_EmptyCollectionsView> createState() => _EmptyCollectionsViewState();
}

class _EmptyCollectionsViewState extends State<_EmptyCollectionsView> {
  late final GamepadNavigation _gamepadNav;

  @override
  void initState() {
    super.initState();
    _gamepadNav = GamepadNavigation(
      onSelectItem: widget.onCreate,
      onXButton: () =>
          HeaderSortDropdown.globalKey.currentState?.showDropdown(),
      onPreviousTab: AppNavigation.previousTab,
      onNextTab: AppNavigation.nextTab,
      onLeftBumper: AppNavigation.previousTab,
      onRightBumper: AppNavigation.nextTab,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'collections_empty',
        onActivate: _gamepadNav.activate,
        onDeactivate: _gamepadNav.deactivate,
      );
    });
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('collections_empty');
    _gamepadNav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;
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
              onPressed: widget.onCreate,
              icon: const Icon(Symbols.add_rounded),
              label: Text(AppLocale.createCollection.getString(context)),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 24.r, vertical: 12.r),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionsCarousel extends StatefulWidget {
  const _CollectionsCarousel({
    required this.collections,
    required this.selectedIndex,
    required this.onSelected,
    required this.onEnter,
    required this.onManage,
    required this.onCreate,
  });

  final List<CollectionModel> collections;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final ValueChanged<int> onEnter;
  final ValueChanged<int> onManage;
  final VoidCallback onCreate;

  @override
  State<_CollectionsCarousel> createState() => _CollectionsCarouselState();
}

class _CollectionsCarouselState extends State<_CollectionsCarousel> {
  final GlobalKey<NativeCarouselState> _carouselKey = GlobalKey();
  late final GamepadNavigation _gamepadNav;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.selectedIndex;
    _gamepadNav = GamepadNavigation(
      onNavigateLeft: () {
        SfxService().playNavSound();
        _carouselKey.currentState?.previousPage();
      },
      onNavigateRight: () {
        SfxService().playNavSound();
        _carouselKey.currentState?.nextPage();
      },
      onSelectItem: () => widget.onEnter(_currentIndex),
      onSettings: () => widget.onManage(_currentIndex),
      onFavorite: widget.onCreate,
      onXButton: () =>
          HeaderSortDropdown.globalKey.currentState?.showDropdown(),
      onPreviousTab: AppNavigation.previousTab,
      onNextTab: AppNavigation.nextTab,
      onLeftBumper: AppNavigation.previousTab,
      onRightBumper: AppNavigation.nextTab,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'collections_carousel',
        onActivate: _gamepadNav.activate,
        onDeactivate: _gamepadNav.deactivate,
      );
    });
  }

  @override
  void didUpdateWidget(_CollectionsCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _currentIndex = widget.selectedIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _carouselKey.currentState?.jumpToPage(_currentIndex);
      });
    }
  }

  @override
  void dispose() {
    GamepadNavigationManager.popLayer('collections_carousel');
    _gamepadNav.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.collections
        .map(
          (collection) =>
              SystemInfo.fromSystemModel(collection.toSystemModel()),
        )
        .toList();
    final current = cards[_currentIndex.clamp(0, cards.length - 1)];
    return Column(
      children: [
        SizedBox(height: 46.r),
        Expanded(
          child: NativeCarousel(
            key: _carouselKey,
            itemCount: cards.length,
            initialIndex: _currentIndex,
            footerHeight: 60.r,
            depth: const CarouselDepth(
              minScale: 0.7,
              opacityBase: 0.75,
              opacityFalloff: 0.55,
              minOpacity: 0.3,
              edgePull: 0.15,
            ),
            itemBuilder: (context, index) => SystemCard(
              info: cards[index],
              isSelected: index == _currentIndex,
              backgroundCacheWidth: 1024,
              onTap: () {
                if (index == _currentIndex) {
                  widget.onEnter(index);
                } else {
                  _carouselKey.currentState?.animateToPage(index);
                }
              },
            ),
            onPageChanged: (index, reason) {
              setState(() => _currentIndex = index);
              widget.onSelected(index);
            },
          ),
        ),
        SystemsGridFooter(
          system: current,
          onEnter: () => widget.onEnter(_currentIndex),
          onSettings: () => widget.onManage(_currentIndex),
          settingsLabel: AppLocale.manage.getString(context),
          onExtra: widget.onCreate,
          extraLabel: AppLocale.createCollection.getString(context),
          extraIconPath: 'assets/images/gamepad/Xbox_Y_button.png',
        ),
      ],
    );
  }
}
