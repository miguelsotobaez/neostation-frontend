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
      onLeftTrigger: _pageBackward,
      onRightTrigger: _pageForward,
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

  /// Moves to the previous/next page (L2/R2), wrapping around. Selection
  /// jumps to the first card of the destination page, matching the fact that
  /// up/down/left/right navigation ([_navigateVirtual]) stays within a page.
  void _pageBackward() {
    if (_totalPages <= 1) return;
    _goToPage((_currentPage - 1 + _totalPages) % _totalPages);
  }

  void _pageForward() {
    if (_totalPages <= 1) return;
    _goToPage((_currentPage + 1) % _totalPages);
  }

  void _goToPage(int page) {
    final pages = _pages;
    if (page < 0 || page >= pages.length) return;

    var offset = 0;
    for (var i = 0; i < page; i++) {
      offset += pages[i].length;
    }

    rebuild(() {
      _currentPage = page;
      _cachedVirtualGrid = null;
    });
    if (pages[page].isNotEmpty) {
      widget.onCardTapped?.call(offset);
    }
  }

  /// Resolve the next focused index based on the current page's virtual
  /// spatial grid — directional navigation stays within the current page;
  /// L2/R2 ([_pageBackward]/[_pageForward]) are what move between pages.
  void _navigateVirtual(String direction) {
    final cards = _currentPageCards;
    final cols = _cols;
    final pageOffset = _currentPageOffset;
    final current = widget.selectedIndex - pageOffset;

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
      widget.onCardTapped?.call(newIndex + pageOffset);
    }
  }

  /// No-op: a page is sized to fill the viewport exactly (see
  /// [_buildWideCardGrid]), so the selected card is always already visible —
  /// there is nothing to scroll to. Going off-page is handled by
  /// [_pageBackward]/[_pageForward], not by scrolling. Kept as a call target
  /// (rather than removed) so callers don't need page-vs-scroll awareness.
  void _ensureSelectedItemVisibleUniversal() {}
}
