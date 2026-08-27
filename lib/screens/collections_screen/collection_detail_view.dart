import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/providers/collection_provider.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/sync/sync_manager.dart';
import 'package:neostation/utils/game_launch_utils.dart';
import 'package:neostation/utils/gamepad_nav.dart';
import 'package:neostation/widgets/confirm_action_dialog.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:provider/provider.dart';

import 'collection_add_games_dialog.dart';
import 'create_edit_collection_dialog.dart';

/// Detailed view for browsing, launching, and managing games in a collection.
class CollectionDetailView extends StatefulWidget {
  final CollectionModel collection;
  final VoidCallback onBack;

  const CollectionDetailView({
    super.key,
    required this.collection,
    required this.onBack,
  });

  @override
  State<CollectionDetailView> createState() => _CollectionDetailViewState();
}

class _CollectionDetailViewState extends State<CollectionDetailView> {
  int _focusedGameIndex = 0;
  final ScrollController _scrollController = ScrollController();
  late final GamepadNavigation _gamepadNav;

  @override
  void initState() {
    super.initState();
    _setupGamepad();
  }

  void _setupGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: () {
        if (_focusedGameIndex > 0) {
          SfxService().playNavSound();
          setState(() => _focusedGameIndex--);
          _scrollToFocused();
        }
      },
      onNavigateDown: () {
        final provider = context.read<CollectionProvider>();
        final maxIdx = provider.activeGames.length - 1;
        if (_focusedGameIndex < maxIdx) {
          SfxService().playNavSound();
          setState(() => _focusedGameIndex++);
          _scrollToFocused();
        }
      },
      onSelectItem: _launchCurrentGame,
      onBack: () {
        SfxService().playBackSound();
        widget.onBack();
      },
      onXButton: _showGameOptions,
      onFavorite: _openManageGames,
    );
    _gamepadNav.initialize();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      GamepadNavigationManager.pushLayer(
        'collection_detail_view',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });
  }

  @override
  void dispose() {
    _gamepadNav.dispose();
    GamepadNavigationManager.popLayer('collection_detail_view');
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToFocused() {
    if (!_scrollController.hasClients) return;
    const itemHeight = 64.0;
    final offset = _focusedGameIndex * itemHeight;
    final viewport = _scrollController.position.viewportDimension;
    final current = _scrollController.offset;

    if (offset < current) {
      _scrollController.jumpTo(offset);
    } else if (offset + itemHeight > current + viewport) {
      _scrollController.jumpTo(offset + itemHeight - viewport);
    }
  }

  Future<void> _launchCurrentGame() async {
    final provider = context.read<CollectionProvider>();
    if (provider.activeGames.isEmpty ||
        _focusedGameIndex >= provider.activeGames.length) {
      return;
    }

    final game = provider.activeGames[_focusedGameIndex];
    final fileProvider = context.read<FileProvider>();
    final syncProvider = context.read<SyncManager>().active;
    if (syncProvider == null) return;

    final system = await SqliteService.getSystemByFolderName(
      game.systemFolderName ?? '',
    );
    if (!mounted) return;

    _gamepadNav.deactivate();

    await launchGameWithDialog(
      context: context,
      game: game,
      system: system,
      fileProvider: fileProvider,
      syncProvider: syncProvider,
      onGameClosed: () {
        _gamepadNav.activate();
      },
      onLaunchFailed: (ctx, result) async {
        if (mounted) {
          AppNotification.showNotification(
            context,
            AppLocale.errorLaunchingGame,
          );
        }
      },
    );
  }

  void _openManageGames() {
    final provider = context.read<CollectionProvider>();
    final currentRomPaths = provider.activeGames
        .map((g) => g.romPath)
        .whereType<String>()
        .toSet();

    CollectionAddGamesDialog.show(
      context: context,
      collectionName: widget.collection.name,
      initialSelectedRomPaths: currentRomPaths,
      onSave: (newRomPaths) async {
        await provider.setGamesForActiveCollection(newRomPaths.toList());
      },
    );
  }

  void _showGameOptions() {
    final provider = context.read<CollectionProvider>();
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    if (provider.activeGames.isEmpty) return;
    final game = provider.activeGames[_focusedGameIndex];

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
                  game.name,
                  style: TextStyle(
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16.h),
                ListTile(
                  leading: const Icon(
                    Symbols.playlist_remove_rounded,
                    color: Colors.redAccent,
                  ),
                  title: Text(
                    AppLocale.removeFromCollection.getString(context),
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _removeCurrentGame(game);
                  },
                ),
                ListTile(
                  leading: Icon(Symbols.edit_rounded, color: primaryColor),
                  title: Text(AppLocale.editCollection.getString(context)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    _editCollection();
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
                    _deleteCollection();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _removeCurrentGame(GameModel game) async {
    final romPath = game.romPath;
    if (romPath == null) return;

    final confirmed = await ConfirmActionDialog.show(
      context,
      title: AppLocale.removeFromCollection.getString(context),
      body: AppLocale.removeFromCollectionConfirm.getString(context),
      confirmLabel: 'Remove',
      icon: Symbols.playlist_remove_rounded,
    );

    if (confirmed && mounted) {
      final provider = context.read<CollectionProvider>();
      await provider.removeGameFromActiveCollection(romPath);
      if (_focusedGameIndex >= provider.activeGames.length &&
          _focusedGameIndex > 0) {
        setState(() => _focusedGameIndex = provider.activeGames.length - 1);
      }
    }
  }

  void _editCollection() {
    final provider = context.read<CollectionProvider>();
    CreateEditCollectionDialog.show(
      context: context,
      collection: widget.collection,
      onSave: (newName) async {
        await provider.updateCollection(widget.collection.id, name: newName);
      },
    );
  }

  Future<void> _deleteCollection() async {
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: AppLocale.deleteCollection.getString(context),
      body: AppLocale.deleteCollectionConfirm.getString(context),
      confirmLabel: 'Delete',
      icon: Symbols.delete_forever_rounded,
    );

    if (confirmed && mounted) {
      final provider = context.read<CollectionProvider>();
      await provider.deleteCollection(widget.collection.id);
      widget.onBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Consumer<CollectionProvider>(
      builder: (context, provider, child) {
        final games = provider.activeGames;
        final selectedGame =
            games.isNotEmpty && _focusedGameIndex < games.length
            ? games[_focusedGameIndex]
            : null;

        return Column(
          children: [
            // Header Bar
            Container(
              padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: theme.cardColor.withValues(alpha: 0.5),
                border: Border(
                  bottom: BorderSide(
                    color: theme.dividerColor.withValues(alpha: 0.2),
                  ),
                ),
              ),
              child: Row(
                children: [
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      onTap: () {
                        SfxService().playBackSound();
                        widget.onBack();
                      },
                      child: Row(
                        children: [
                          Icon(
                            Symbols.arrow_back_rounded,
                            size: 20.r,
                            color: primaryColor,
                          ),
                          SizedBox(width: 6.w),
                          Text(
                            'Back [B]',
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(width: 16.w),
                  Container(
                    height: 20.h,
                    width: 1.w,
                    color: theme.dividerColor.withValues(alpha: 0.3),
                  ),
                  SizedBox(width: 16.w),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.collection.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: 10.w,
                      vertical: 4.h,
                    ),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(
                        color: primaryColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '${games.length} games',
                      style: TextStyle(
                        fontSize: 12.sp,
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
                        horizontal: 14.w,
                        vertical: 8.h,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                    ),
                    icon: Icon(Symbols.add_rounded, size: 18.r),
                    label: const Text('Add Games [Y]'),
                    onPressed: _openManageGames,
                  ),
                ],
              ),
            ),

            // Content Area
            Expanded(
              child: provider.isLoadingGames
                  ? const Center(child: CircularProgressIndicator())
                  : games.isEmpty
                  ? _buildEmptyState(context, primaryColor)
                  : Row(
                      children: [
                        // Games List (Left 50%)
                        Expanded(
                          flex: 5,
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.symmetric(vertical: 8.h),
                            itemCount: games.length,
                            itemExtent: 60.h,
                            itemBuilder: (context, index) {
                              final game = games[index];
                              final isFocused = index == _focusedGameIndex;

                              return MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() => _focusedGameIndex = index);
                                    _launchCurrentGame();
                                  },
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 120),
                                    margin: EdgeInsets.symmetric(
                                      horizontal: 14.w,
                                      vertical: 3.h,
                                    ),
                                    padding: EdgeInsets.symmetric(
                                      horizontal: 14.w,
                                      vertical: 8.h,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isFocused
                                          ? primaryColor.withValues(alpha: 0.18)
                                          : theme.cardColor.withValues(
                                              alpha: 0.35,
                                            ),
                                      borderRadius: BorderRadius.circular(10.r),
                                      border: Border.all(
                                        color: isFocused
                                            ? primaryColor
                                            : theme.dividerColor.withValues(
                                                alpha: 0.15,
                                              ),
                                        width: isFocused ? 2.r : 1.r,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(
                                          Symbols.videogame_asset_rounded,
                                          size: 20.r,
                                          color: isFocused
                                              ? primaryColor
                                              : theme.hintColor,
                                        ),
                                        SizedBox(width: 10.w),
                                        Expanded(
                                          child: Text(
                                            game.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14.sp,
                                              fontWeight: isFocused
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
                                        ),
                                        if (game.systemRealName != null)
                                          Container(
                                            padding: EdgeInsets.symmetric(
                                              horizontal: 8.w,
                                              vertical: 2.h,
                                            ),
                                            decoration: BoxDecoration(
                                              color: theme.cardColor.withValues(
                                                alpha: 0.7,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6.r),
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

                        // Divider
                        Container(
                          width: 1.w,
                          color: theme.dividerColor.withValues(alpha: 0.15),
                        ),

                        // Selected Game Details Panel (Right 50%)
                        Expanded(
                          flex: 5,
                          child: selectedGame == null
                              ? const SizedBox.shrink()
                              : _buildGameDetailsPanel(
                                  context,
                                  selectedGame,
                                  primaryColor,
                                ),
                        ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmptyState(BuildContext context, Color primaryColor) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: EdgeInsets.all(32.r),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.folder_open_rounded,
              size: 56.r,
              color: primaryColor.withValues(alpha: 0.6),
            ),
            SizedBox(height: 16.h),
            Text(
              AppLocale.emptyCollectionTitle.getString(context),
              style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8.h),
            Text(
              AppLocale.emptyCollectionSubtitle.getString(context),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.sp, color: theme.hintColor),
            ),
            SizedBox(height: 20.h),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
              ),
              icon: const Icon(Symbols.add_rounded),
              label: const Text('Add Games [Y]'),
              onPressed: _openManageGames,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameDetailsPanel(
    BuildContext context,
    GameModel game,
    Color primaryColor,
  ) {
    final theme = Theme.of(context);
    final desc = game.descriptions?['en'] ?? '';

    return Padding(
      padding: EdgeInsets.all(20.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            game.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 6.h,
            children: [
              if (game.systemRealName != null &&
                  game.systemRealName!.isNotEmpty)
                _buildBadge(game.systemRealName!, primaryColor),
              if (game.year.isNotEmpty) _buildBadge(game.year, primaryColor),
              if (game.genre.isNotEmpty) _buildBadge(game.genre, primaryColor),
              if (game.developer.isNotEmpty)
                _buildBadge(game.developer, primaryColor),
            ],
          ),
          SizedBox(height: 16.h),
          if (desc.isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  desc,
                  style: TextStyle(
                    fontSize: 13.sp,
                    height: 1.4,
                    color: theme.textTheme.bodyMedium?.color?.withValues(
                      alpha: 0.85,
                    ),
                  ),
                ),
              ),
            )
          else
            const Spacer(),
          SizedBox(height: 16.h),
          Row(
            children: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: 20.w,
                    vertical: 12.h,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
                icon: const Icon(Symbols.play_arrow_rounded),
                label: const Text('Play [A]'),
                onPressed: _launchCurrentGame,
              ),
              SizedBox(width: 12.w),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(
                    horizontal: 14.w,
                    vertical: 12.h,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
                icon: const Icon(Symbols.more_horiz_rounded),
                label: const Text('Options [X]'),
                onPressed: _showGameOptions,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color primaryColor) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.w600,
          color: primaryColor,
        ),
      ),
    );
  }
}
