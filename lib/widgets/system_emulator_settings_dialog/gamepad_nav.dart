part of '../system_emulator_settings_dialog.dart';

/// Gamepad/keyboard navigation for the emulator settings dialog.
///
/// Moves the input-handling slice of [_SystemEmulatorSettingsDialogState] out of
/// the monolith — behaviour is unchanged. All state lives on the host [State];
/// extensions can't declare fields. `setState` calls route through the host
/// [rebuild] bridge (`State.setState` is `@protected` and can't be invoked from
/// an extension).
extension _GamepadNav on _SystemEmulatorSettingsDialogState {
  void _initializeGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: _navigateUp,
      onNavigateDown: _navigateDown,
      onPreviousTab: _previousTab,
      onNextTab: _nextTab,
      onSelectItem: _handleSelectItem,
      onBack: _closeDialog,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'system_emulator_settings_dialog',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });
  }

  void _cleanupGamepad() {
    GamepadNavigationManager.popLayer('system_emulator_settings_dialog');
    _gamepadNav.dispose();
  }

  void _navigateUp() {
    if (_openMenuIndex != -1) {
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      if (focusedContext != null) {
        Actions.invoke(
          focusedContext,
          const DirectionalFocusIntent(TraversalDirection.up),
        );
      }
      return;
    }
    if (_currentTab == 1) {
      if (_totalEmulators == 0) return;

      int newIndex = _selectedIndex;
      // Find previous selectable item (skip headers)
      for (int i = 1; i <= _totalEmulators; i++) {
        final candidate = (newIndex - i + _totalEmulators) % _totalEmulators;
        if (_displayItems[candidate] is! EmulatorHeaderItem) {
          rebuild(() {
            _selectedIndex = candidate;
          });
          break;
        }
      }

      _centeredScrollController.updateSelectedIndex(_selectedIndex);
      _scrollToSelected();
    } else if (_currentTab == 0) {
      rebuild(() {
        _generalIndex =
            (_generalIndex - 1 + _totalGeneralItems) % _totalGeneralItems;
      });
      _scrollToGeneralSelected();
    } else if (_currentTab == 2) {
      rebuild(() {
        _appearanceIndex = (_appearanceIndex - 1 + 2) % 2;
      });
      _scrollToAppearanceSelected();
    }
  }

  void _navigateDown() {
    if (_openMenuIndex != -1) {
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      if (focusedContext != null) {
        Actions.invoke(
          focusedContext,
          const DirectionalFocusIntent(TraversalDirection.down),
        );
      }
      return;
    }
    if (_currentTab == 1) {
      if (_totalEmulators == 0) return;

      int newIndex = _selectedIndex;
      // Find next selectable item (skip headers)
      for (int i = 1; i <= _totalEmulators; i++) {
        final candidate = (newIndex + i) % _totalEmulators;
        if (_displayItems[candidate] is! EmulatorHeaderItem) {
          rebuild(() {
            _selectedIndex = candidate;
          });
          break;
        }
      }

      _centeredScrollController.updateSelectedIndex(_selectedIndex);
      _scrollToSelected();
    } else if (_currentTab == 0) {
      rebuild(() {
        _generalIndex = (_generalIndex + 1) % _totalGeneralItems;
      });
      _scrollToGeneralSelected();
    } else if (_currentTab == 2) {
      rebuild(() {
        _appearanceIndex = (_appearanceIndex + 1) % 2;
      });
      _scrollToAppearanceSelected();
    }
  }

  void _previousTab() {
    List<int> availableTabs = [0, 2];
    if (widget.system.folderName != 'all' &&
        widget.system.folderName != 'android') {
      availableTabs = [0, 1, 2];
    }

    int currentIndex = availableTabs.indexOf(_currentTab);
    int prevIndex =
        (currentIndex - 1 + availableTabs.length) % availableTabs.length;
    rebuild(() {
      _currentTab = availableTabs[prevIndex];
    });
  }

  void _nextTab() {
    List<int> availableTabs = [0, 2];
    if (widget.system.folderName != 'all' &&
        widget.system.folderName != 'android') {
      availableTabs = [0, 1, 2];
    }

    int currentIndex = availableTabs.indexOf(_currentTab);
    int nextIndex = (currentIndex + 1) % availableTabs.length;
    rebuild(() {
      _currentTab = availableTabs[nextIndex];
    });
  }

  void _handleSelectItem() {
    if (_openMenuIndex != -1) {
      final focusedContext = FocusManager.instance.primaryFocus?.context;
      if (focusedContext != null) {
        Actions.invoke(focusedContext, const ActivateIntent());
      }
      return;
    }
    if (_currentTab == 1) {
      _setSelectedAsDefault();
    } else if (_currentTab == 0) {
      if (_generalIndex == 0) {
        _togglePreferFileName(!_system.preferFileName);
      } else if (_generalIndex == 1) {
        _toggleHideExtension(!_system.hideExtension);
      } else if (_generalIndex == 2) {
        _toggleHideParentheses(!_system.hideParentheses);
      } else if (_generalIndex == 3) {
        _toggleHideBrackets(!_system.hideBrackets);
      } else if (_generalIndex == 4 &&
          widget.system.folderName != 'all' &&
          widget.system.folderName != 'android') {
        _toggleRecursiveScan(!_system.recursiveScan);
      }
    } else if (_currentTab == 2) {
      if (_appearanceIndex == 0) {
        _pickAndSaveImage();
      } else if (_appearanceIndex == 1) {
        _pickAndSaveLogoImage();
      }
    }
  }
}
