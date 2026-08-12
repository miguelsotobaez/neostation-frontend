part of '../my_games_list.dart';

/// Favorite toggling and list re-sorting for the system games list.
///
/// Keeps favorites-first / alphabetical ordering in sync after a favorite
/// toggle or a re-scrape, preserving the user's visual focus position. All
/// state lives on the host [State]; this extension only moves the methods out
/// of the monolith — behaviour is unchanged. The `setState` calls route through
/// the host [rebuild] bridge (`State.setState` is `@protected` and can't be
/// invoked from an extension).
extension _FavoritesReorder on _SystemGamesListState {
  /// Toggles the 'favorite' status for the selected game and re-sorts the list.
  Future<void> _toggleFavorite() async {
    if (_selectedGame == null) return;

    if (widget.system.folderName == 'music') {
      try {
        final configProvider = context.read<SqliteConfigProvider>();
        await GameService.toggleFavorite(_selectedGame!);
        if (!mounted) return;
        await configProvider.refreshDetectedSystems();

        rebuild(() {
          final gameIndex = _games.indexWhere(
            (g) => g.romname == _selectedGame!.romname,
          );
          if (gameIndex != -1) {
            final currentFavorite = _games[gameIndex].isFavorite ?? false;
            _games[gameIndex] = _games[gameIndex].copyWith(
              isFavorite: !currentFavorite,
            );
            _selectedGame = _games[gameIndex];
          }
        });

        _reorderGamesListKeepingVisualPosition();
      } catch (e) {
        _SystemGamesListState._log.e('Error toggling music favorite: $e');
      }
      return;
    }

    try {
      final configProvider = context.read<SqliteConfigProvider>();
      await GameService.toggleFavorite(_selectedGame!);

      if (!mounted) return;
      await configProvider.refreshDetectedSystems();

      rebuild(() {
        final gameIndex = _games.indexWhere(
          (game) => game.romname == _selectedGame!.romname,
        );
        if (gameIndex != -1) {
          final currentFavorite = _games[gameIndex].isFavorite ?? false;
          _games[gameIndex] = _games[gameIndex].copyWith(
            isFavorite: !currentFavorite,
          );
          _selectedGame = _games[gameIndex];
        }
      });

      _reorderGamesListKeepingVisualPosition();
    } catch (error) {
      if (!mounted) return;
      _SystemGamesListState._log.e('Error toggling favorite: $error');
      if (!mounted) return;
      AppNotification.showNotification(
        context,
        AppLocale.errorUpdatingFavorite.getString(context),
        type: NotificationType.error,
      );
    }
  }

  /// Re-sorts the game collection (Favorites first, then Alphabetical) while
  /// preserving the user's current scroll/focus index for a seamless experience.
  void _reorderGamesListKeepingVisualPosition() {
    if (_selectedGame == null) return;

    final oldIndex = _selectedGameIndex;

    rebuild(() {
      final sortedGames = List<GameModel>.from(_games);

      sortedGames.sort((a, b) {
        if (a.isFavorite == true && b.isFavorite != true) return -1;
        if (a.isFavorite != true && b.isFavorite == true) return 1;
        return a.name.compareTo(b.name);
      });

      _games = sortedGames;
      _gameIndexMap = {for (int i = 0; i < _games.length; i++) _games[i]: i};

      if (oldIndex >= 0 && oldIndex < _games.length) {
        _selectedGameIndex = oldIndex;
        _selectedGame = _games[oldIndex];
      } else if (_games.isNotEmpty) {
        _selectedGameIndex = 0;
        _selectedGame = _games.first;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToSelectedItem();
      }
    });
  }

  /// Sorts the list and re-anchors focus to a specific ROM.
  /// Primarily used after scraping to follow a game to its new alphabetical position.
  void _reorderGamesListFollowingGame(String romname) {
    rebuild(() {
      final sortedGames = List<GameModel>.from(_games);
      sortedGames.sort((a, b) {
        if (a.isFavorite == true && b.isFavorite != true) return -1;
        if (a.isFavorite != true && b.isFavorite == true) return 1;
        return a.name.compareTo(b.name);
      });
      _games = sortedGames;
      _gameIndexMap = {for (int i = 0; i < _games.length; i++) _games[i]: i};

      final newIndex = _games.indexWhere((g) => g.romname == romname);
      if (newIndex != -1) {
        _selectedGameIndex = newIndex;
        _selectedGame = _games[newIndex];
      } else if (_games.isNotEmpty) {
        _selectedGameIndex = 0;
        _selectedGame = _games.first;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToSelectedItem();
    });
  }
}
