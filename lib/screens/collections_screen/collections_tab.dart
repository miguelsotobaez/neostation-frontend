import 'package:flutter/material.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/providers/collection_provider.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/screens/game_screen/my_games_list.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:provider/provider.dart';

import 'collections_overview.dart';

/// Top-level container for the Collections navigation tab.
///
/// Displays the collections overview and routes to [SystemGamesList] using
/// standard platform view components when a collection is selected.
class CollectionsTab extends StatefulWidget {
  const CollectionsTab({super.key});

  @override
  State<CollectionsTab> createState() => _CollectionsTabState();
}

class _CollectionsTabState extends State<CollectionsTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CollectionProvider>().loadCollections();
    });
  }

  void _openCollection(CollectionModel col) async {
    final fileProvider = Provider.of<FileProvider>(context, listen: false);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SystemGamesList(
          system: col.toSystemModel(),
          fileProvider: fileProvider,
        ),
      ),
    );

    if (mounted) {
      context.read<CollectionProvider>().loadCollections();
      GamepadNavigationManager.reactivate();
    }
  }

  @override
  Widget build(BuildContext context) {
    return CollectionsOverview(onSelectCollection: _openCollection);
  }
}
