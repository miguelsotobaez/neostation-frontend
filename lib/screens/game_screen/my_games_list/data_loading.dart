part of '../my_games_list.dart';

/// Data-loading for the system games list.
///
/// Fetches the game collection for the active system and the localized
/// description for the selected game. All state lives on the host [State]; this
/// extension only moves the methods out of the monolith — behaviour is
/// unchanged. `setState` calls route through the host [rebuild] bridge
/// (`State.setState` is `@protected` and can't be invoked from an extension),
/// and the host's static `_log` is qualified as `_SystemGamesListState._log`.
extension _DataLoading on _SystemGamesListState {
  /// Retrieves localized game descriptions directly from the SQLite database.
  void _loadLocalizedDescription() async {
    if (_selectedGame == null) return;

    try {
      String? systemId;

      // In 'Global Library' mode, resolve the game's native hardware system ID.
      if ((widget.system.folderName == 'all' ||
              widget.system.folderName == SystemFolderNames.favorites) &&
          _selectedGame!.systemFolderName != null) {
        final originalSystem = await SystemRepository.getSystemByFolderName(
          _selectedGame!.systemFolderName!,
        );
        systemId = originalSystem?.id;
      } else {
        systemId = widget.system.id;
      }

      if (systemId == null) {
        if (mounted) {
          rebuild(() {
            _localizedDescription = null;
          });
        }
        return;
      }

      final description = await GameRepository.getLocalizedDescription(
        _selectedGame!.romname,
        systemId,
      );

      if (mounted &&
          _selectedGame != null &&
          _selectedGame!.romname == _selectedGame!.romname) {
        rebuild(() {
          _localizedDescription = description;
        });
      }
    } catch (e) {
      _SystemGamesListState._log.e('Localized description loading failed: $e');
      if (mounted) {
        rebuild(() {
          _localizedDescription = null;
        });
      }
    }
  }

  Future<void> _loadGames() async {
    if (!mounted || _isLoadingGames) return;
    _isLoadingGames = true;

    final isInitialLoad = _games.isEmpty;
    if (isInitialLoad) {
      rebuild(() => _isLoading = true);
    }

    try {
      final games = await GameService.loadGamesForSystem(widget.system);
      if (!mounted) return;

      _SystemGamesListState._log.i(
        'SystemGamesList: Loaded ${games.length} games for ${widget.system.folderName}',
      );
      if (widget.system.folderName == 'music' && games.isNotEmpty) {
        _SystemGamesListState._log.i(
          'SystemGamesList: First 3 music tracks: ${games.take(3).map((g) => g.name).toList()}',
        );
      }
      rebuild(() {
        _games = games;
        _gameIndexMap = {for (int i = 0; i < games.length; i++) games[i]: i};

        // Music system specialization: Anchor initial focus to the currently active track.
        if (widget.system.folderName == 'music') {
          final musicService = MusicPlayerService();
          if (musicService.isStarted && musicService.currentTrack != null) {
            final playingTrackPath = musicService.currentTrack?.romPath;
            final playingIndex = games.indexWhere(
              (g) => g.romPath == playingTrackPath,
            );

            if (playingIndex != -1) {
              _selectedGameIndex = playingIndex;
              _selectedGame = games[playingIndex];
              _SystemGamesListState._log.i(
                'SystemGamesList: Initial focus set to playing track at index $playingIndex',
              );
            }
          }
        }

        if (widget.initialRomPath != null &&
            widget.initialRomPath!.isNotEmpty) {
          final initialIndex = games.indexWhere(
            (game) => game.romPath == widget.initialRomPath,
          );
          if (initialIndex != -1) {
            _selectedGameIndex = initialIndex;
            _selectedGame = games[initialIndex];
          } else {
            _selectedGameIndex = 0;
            _selectedGame = games.isNotEmpty ? games.first : null;
          }
        } else if (_selectedGame != null &&
            widget.system.folderName != 'music') {
          // Persistent Selection Logic: Retain current index if the game still exists post-reload.
          final selectedIndex = games.indexWhere(
            (game) => game.romname == _selectedGame!.romname,
          );
          if (selectedIndex != -1) {
            _selectedGameIndex = selectedIndex;
            _selectedGame = games[selectedIndex];
          } else {
            _selectedGameIndex = 0;
            _selectedGame = games.isNotEmpty ? games.first : null;
          }
        } else if (_selectedGame == null) {
          _selectedGameIndex = 0;
          _selectedGame = games.isNotEmpty ? games.first : null;
        }
        _isLoading = false;
      });

      // Trigger deferred media and background tasks after initial UI render.
      if (_selectedGame != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _startVideoTimer();
          _performBackgroundOperationsForSelectedGame();
          // Reveal a deep-linked selection (search "Go to game", RA dashboard)
          // in the list; without this it is selected but stays off-screen.
          if (isInitialLoad && _selectedGameIndex > 0) {
            _scrollToSelectedItem();
          }
        });
      }
    } catch (e) {
      _SystemGamesListState._log.e('Error loading games: $e');
    } finally {
      if (mounted) {
        rebuild(() => _isLoading = false);
        _isLoadingGames = false;
      }
    }
  }
}
