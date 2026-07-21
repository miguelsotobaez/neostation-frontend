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

  /// Handles Select button (View/Share) for mute refresh depending on the
  /// active details tab.
  void _handleSelectButton() {
    SfxService().playNavSound();
    _selectButtonAction?.call();
  }

  /// Handles the X button: opens the game view-mode picker (list/grid/carousel
  /// + card size/style). For the music library, X keeps its shuffle toggle.
  void _handleXButton() {
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
      return;
    }
    GameViewModeDropdown.globalKey.currentState?.showDropdown();
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
      onXButton: _handleXButton, // Button X - View mode picker (music: shuffle).
      onSettings: _openGameSettingsDialog, // Button Start.
      onSelectButton: _handleSelectButton, // Button Select (View) - tap.
      onSelectModifierA: () => _scrapeAction?.call(), // Select + A - Scrape.
      onSelectModifierB: _toggleLegend, // Select + B - Hide/show legend.
      onSelectModifierY: _showRandomGameDialog, // Select + Y - Random.
      onRightStickClick: null,
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
