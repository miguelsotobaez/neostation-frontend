part of '../my_systems_grid.dart';

/// Gamepad/keyboard grid navigation for the systems grid.
///
/// The input-driven slice of [_SystemCardGridViewState] — gamepad layer setup,
/// directional grid traversal (row/column virtual-grid walk), and keeping the
/// selected card scrolled into view — moved out of the monolith. Behaviour is
/// unchanged. State lives on the host [State] (extensions can't declare fields);
/// `setState` calls route through the host [rebuild] bridge (`State.setState` is
/// `@protected` and can't be invoked from an extension).
extension _GamepadGridNav on _SystemCardGridViewState {
  /// Configures the gamepad navigation layer for the systems grid.
  void _initializeGamepad() {
    _gamepadNav = GamepadNavigation(
      onNavigateUp: (isRepeat) {
        if (_isNavigatingFast != isRepeat) {
          rebuild(() => _isNavigatingFast = isRepeat);
        }
        _navigateGrid('up');
      },
      onNavigateDown: (isRepeat) {
        if (_isNavigatingFast != isRepeat) {
          rebuild(() => _isNavigatingFast = isRepeat);
        }
        _navigateGrid('down');
      },
      onNavigateLeft: (isRepeat) {
        if (_isNavigatingFast != isRepeat) {
          rebuild(() => _isNavigatingFast = isRepeat);
        }
        _navigateGrid('left');
      },
      onNavigateRight: (isRepeat) {
        if (_isNavigatingFast != isRepeat) {
          rebuild(() => _isNavigatingFast = isRepeat);
        }
        _navigateGrid('right');
      },
      onSelectItem: () => widget.onEnterPressed?.call(),
      onSettings: () => widget.onEscapePressed?.call(),
      onXButton: () {
        HeaderSortDropdown.globalKey.currentState?.showDropdown();
      },
      onPreviousTab: AppNavigation.previousTab,
      onNextTab: AppNavigation.nextTab,
      onLeftBumper: AppNavigation.previousTab,
      onRightBumper: AppNavigation.nextTab,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _gamepadNav.initialize();
      GamepadNavigationManager.pushLayer(
        'my_systems_list',
        onActivate: () => _gamepadNav.activate(),
        onDeactivate: () => _gamepadNav.deactivate(),
      );
    });
  }

  void _cleanupGamepad() {
    GamepadNavigationManager.popLayer('my_systems_list');
    _gamepadNav.dispose();
  }

  void _navigateGrid(String direction) {
    if (!mounted) return;
    _navigateVirtual(direction);
  }

  /// Resolve the next focused index based on the virtual spatial grid.
  void _navigateVirtual(String direction) {
    final cards = _systemCards;
    final cols = _cols;
    final current = widget.selectedIndex;

    final grid = _buildVirtualGrid(cards, cols);

    // Resolve current 2D coordinates.
    int curRow = -1, curCol = -1;
    outer:
    for (int r = 0; r < grid.length; r++) {
      for (int c = 0; c < cols; c++) {
        if (grid[r][c] == current) {
          curRow = r;
          curCol = c;
          break outer;
        }
      }
    }
    if (curRow == -1) return;

    int newIndex = current;

    switch (direction) {
      case 'up':
        int targetRow = curRow;
        int idx = current;
        int safety = 0;
        while ((idx == current || idx == -1) && safety < grid.length) {
          targetRow = (targetRow - 1 + grid.length) % grid.length;
          idx = grid[targetRow][curCol.clamp(0, cols - 1)];
          if (idx == -1) {
            idx = findNearestInRow(grid, targetRow, curCol.clamp(0, cols - 1));
          }
          safety++;
        }
        newIndex = idx >= 0 ? idx : current;
      case 'down':
        int targetRow = curRow;
        int idx = current;
        int safety = 0;
        while ((idx == current || idx == -1) && safety < grid.length) {
          targetRow = (targetRow + 1) % grid.length;
          idx = grid[targetRow][curCol.clamp(0, cols - 1)];
          if (idx == -1) {
            idx = findNearestInRow(grid, targetRow, curCol.clamp(0, cols - 1));
          }
          safety++;
        }
        newIndex = idx >= 0 ? idx : current;
      case 'left':
        int firstCol = curCol;
        while (firstCol > 0 && grid[curRow][firstCol - 1] == current) {
          firstCol--;
        }
        if (firstCol > 0) {
          final idx = grid[curRow][firstCol - 1];
          newIndex = idx >= 0 ? idx : current;
        } else {
          int targetRow = (curRow - 1 + grid.length) % grid.length;
          for (int c = cols - 1; c >= 0; c--) {
            if (grid[targetRow][c] != -1 && grid[targetRow][c] != current) {
              newIndex = grid[targetRow][c];
              break;
            }
          }
        }
      case 'right':
        int lastCol = curCol;
        while (lastCol < cols - 1 && grid[curRow][lastCol + 1] == current) {
          lastCol++;
        }
        if (lastCol < cols - 1) {
          final idx = grid[curRow][lastCol + 1];
          newIndex = idx >= 0 ? idx : current;
        } else {
          int targetRow = (curRow + 1) % grid.length;
          for (int c = 0; c < cols; c++) {
            if (grid[targetRow][c] != -1 && grid[targetRow][c] != current) {
              newIndex = grid[targetRow][c];
              break;
            }
          }
        }
    }

    if (newIndex != current) {
      widget.onCardTapped?.call(newIndex);
    }
  }

  /// Automatically adjusts scroll position to keep the selected item centered in the viewport.
  void _ensureSelectedItemVisibleUniversal() {
    if (!_scrollController.hasClients || widget.systems.isEmpty) return;

    final cards = _systemCards;
    final cols = _cols;
    final grid = _buildVirtualGrid(cards, cols);

    int selectedRow = -1;
    for (int r = 0; r < grid.length; r++) {
      if (grid[r].contains(widget.selectedIndex)) {
        selectedRow = r;
        break;
      }
    }
    if (selectedRow == -1) return;

    final selectedCard = cards[widget.selectedIndex];
    final spanH = (selectedCard.isGame && cols >= 3) ? 2 : 1;

    final dimensions = _calculateGridDimensions();
    final rowHeight = dimensions['rowHeight']!;
    final itemHeight = dimensions['itemHeight']!;
    final mainAxisSpacing = dimensions['mainAxisSpacing']!;

    final viewportHeight = _scrollController.position.viewportDimension;
    final maxScrollExtent = _scrollController.position.maxScrollExtent;
    final minScrollExtent = _scrollController.position.minScrollExtent;

    final double itemActualHeight =
        spanH * itemHeight + (spanH - 1) * mainAxisSpacing;

    final double itemTop = selectedRow * rowHeight;
    final double itemCenter = itemTop + (itemActualHeight / 2);

    final double targetOffset = (itemCenter - (viewportHeight / 2)).clamp(
      minScrollExtent,
      maxScrollExtent,
    );

    _scrollController.animateTo(
      targetOffset,
      duration: _isNavigatingFast
          ? const Duration(milliseconds: 180)
          : const Duration(milliseconds: 360),
      curve: Curves.easeOutQuart,
    );
  }
}
