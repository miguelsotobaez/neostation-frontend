part of '../my_games_list.dart';

/// Gamepad / keyboard input handling for the system games list.
///
/// Registers the [GamepadNavigation] input mappings and implements the
/// navigation-dispatch handlers (D-pad move, page jump, bumpers, Start). All
/// state lives on the host [State]; this extension only moves the methods out
/// of the monolith — behaviour is unchanged.
extension _GamepadNav on _SystemGamesListState {
  /// Handles Right Bumper (RB) interactions for tab navigation or scraping.
  Future<void> _handleRightBumper() async {
    if (_tabNavigationAction != null && _tabNavigationAction!(true)) {
      return;
    }
    _secondaryOverlayAction?.call();
  }

  /// Handles Left Bumper (LB) interactions for tab navigation.
  Future<void> _handleLeftBumper() async {
    if (_tabNavigationAction != null && _tabNavigationAction!(false)) {
      return;
    }
  }

  /// Registers gamepad and keyboard input mappings for the screen.
  void _initializeGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: _navigateUp,
      onNavigateDown: _navigateDown,
      onNavigateLeft: _navigateLeft, // Page Up (10 items).
      onNavigateRight: _navigateRight, // Page Down (10 items).
      onSelectItem: _selectCurrentGame,
      onBack: _goBack,
      onFavorite: _toggleFavorite, // Button Y.
      onXButton: () {
        GameViewModeDropdown.globalKey.currentState?.showDropdown();
      }, // Button X - View mode.
      onSettings: _handleStartButton, // Button Start.
      onLeftStickClick: () {
        if (widget.system.folderName == 'music') {
          final service = MusicPlayerService();
          service.toggleShuffle();
          AppNotification.showNotification(
            context,
            service.isShuffle
                ? AppLocale.shuffleEnabled.getString(context)
                : AppLocale.shuffleDisabled.getString(context),
            type: NotificationType.info,
          );
        } else {
          _showRandomGameDialog();
        }
      }, // L3 - Random.
      onRightStickClick: null,
      onSelectButton: () {
        if (widget.system.folderName == 'music') {
          final service = MusicPlayerService();
          final isLooping = service.isCurrentTrackLooping;
          if (!isLooping) {
            if (_selectedGame != null) {
              // setState is @protected and cannot be called from an extension,
              // so route through the host's [rebuild] bridge (behaviourally
              // identical).
              rebuild(() {
                _games.removeAt(_selectedGameIndex);
                _games.insert(0, _selectedGame!);
                _selectedGameIndex = 0;
              });
              service.setPlaylist(_games);
              service.setLoop(true, trackPath: _selectedGame!.romPath);
              _scrollToSelectedItem();
              AppNotification.showNotification(
                context,
                AppLocale.loopActivated.getString(context),
                type: NotificationType.success,
              );
            }
          } else {
            service.setLoop(false);
            AppNotification.showNotification(
              context,
              AppLocale.loopDeactivated.getString(context),
              type: NotificationType.info,
            );
          }
          return;
        }
        // Scrape the selected game directly, matching the grid/carousel views.
        // Routing through the details card's secondary action early-returns when
        // the secondary display is active (e.g. AYN Thor), so scraping never ran.
        _onScrapeCurrentGame();
      }, // Select - Scrape.
      onLeftBumper: _handleLeftBumper,
      onRightBumper: _handleRightBumper,
      onPreviousTab: _handleLeftBumper, // Key Q.
      onNextTab: _handleRightBumper, // Key E.
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'system_games_list',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });
  }

  void _handleStartButton() {
    if (_startActionCallback != null) {
      _startActionCallback!();
    }
  }

  /// Moves focus to the previous game in the list.
  void _navigateUp() {
    if (_games.isEmpty) return;

    if (_isAchievementsOpen != null && _isAchievementsOpen!()) {
      _moveAchievementUp?.call();
      return;
    }

    _resetVideoState();
    _updateSelectedGame(
      (_selectedGameIndex - 1 + _games.length) % _games.length,
    );
  }

  /// Moves focus to the next game in the list.
  void _navigateDown() {
    if (_games.isEmpty) return;

    if (_isAchievementsOpen != null && _isAchievementsOpen!()) {
      _moveAchievementDown?.call();
      return;
    }

    _resetVideoState();
    _updateSelectedGame((_selectedGameIndex + 1) % _games.length);
  }

  /// Jumps back by 10 games (Page Up logic).
  void _navigateLeft() {
    if (_games.isEmpty) return;

    if (_isAchievementsOpen != null && _isAchievementsOpen!()) {
      _moveAchievementLeft?.call();
      return;
    }

    _resetVideoState();
    final newIndex = (_selectedGameIndex - 10 + _games.length) % _games.length;
    _updateSelectedGame(newIndex);
  }

  /// Jumps forward by 10 games (Page Down logic).
  void _navigateRight() {
    if (_games.isEmpty) return;

    if (_isAchievementsOpen != null && _isAchievementsOpen!()) {
      _moveAchievementRight?.call();
      return;
    }

    _resetVideoState();
    final newIndex = (_selectedGameIndex + 10) % _games.length;
    _updateSelectedGame(newIndex);
  }
}
