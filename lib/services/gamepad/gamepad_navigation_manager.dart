import 'package:neostation/services/logger_service.dart';

/// Represents a single layer in the navigation stack for gamepad focus management.
class NavLayer {
  final String id;
  final void Function() onActivate;
  final void Function() onDeactivate;

  /// Whether this layer belongs to a modal surface that must keep input focus
  /// until it is dismissed. See [GamepadNavigationManager.pushLayer].
  final bool modal;

  NavLayer({
    required this.id,
    required this.onActivate,
    required this.onDeactivate,
    this.modal = false,
  });
}

/// Global manager for gamepad/keyboard navigation focus across the application.
///
/// Maintains a focus stack to ensure that only the topmost UI layer receives
/// input events, preventing "ghost" navigation in background screens.
class GamepadNavigationManager {
  static final _log = LoggerService.instance;
  static final List<NavLayer> _stack = [];

  /// Pushes a new navigation layer to the top of the stack and activates it.
  ///
  /// Automatically deactivates the previously active layer.
  ///
  /// Set [modal] for layers owned by a modal surface (dialogs). A modal layer
  /// cannot be displaced by a later non-modal push: background widgets that
  /// mount while the dialog is open are inserted *beneath* it instead, keeping
  /// their registration without taking input focus. Without this, a widget that
  /// appears late — e.g. the systems grid mounting when the startup ROM scan
  /// finishes behind the systems-update dialog — pushed itself on top and stole
  /// the controller, so A opened a system behind the dialog.
  ///
  /// CAVEAT: anything a modal opens *on top of itself* (a dropdown, an option
  /// picker) must be pushed with [modal] too, or it lands underneath its own
  /// parent and never receives input. Only mark self-contained dialogs modal.
  static void pushLayer(
    String id, {
    required void Function() onActivate,
    required void Function() onDeactivate,
    bool modal = false,
  }) {
    _log.i('[GamepadNavigationManager] Pushing layer: $id (modal: $modal)');

    // A non-modal layer never displaces an open modal. Slot it below the
    // lowest modal so the dialogs above it stay ordered, and so it becomes the
    // active layer once they are all dismissed.
    final firstModal = _stack.indexWhere((layer) => layer.modal);
    if (!modal && firstModal != -1) {
      _log.i(
        '[GamepadNavigationManager] Modal ${_stack[firstModal].id} holds focus; '
        'inserting $id beneath it',
      );
      _stack.insert(
        firstModal,
        NavLayer(
          id: id,
          onActivate: onActivate,
          onDeactivate: onDeactivate,
          modal: modal,
        ),
      );
      // Not activated: the modal above keeps focus. The new layer starts
      // inactive, which is the state a freshly built navigator is already in.
      return;
    }

    if (_stack.isNotEmpty) {
      _log.d(
        '[GamepadNavigationManager] Deactivating previous layer: ${_stack.last.id}',
      );
      try {
        _stack.last.onDeactivate();
      } catch (e) {
        _log.e('Error deactivating layer ${_stack.last.id}: $e');
      }
    }

    final newLayer = NavLayer(
      id: id,
      onActivate: onActivate,
      onDeactivate: onDeactivate,
      modal: modal,
    );
    _stack.add(newLayer);

    try {
      onActivate();
    } catch (e) {
      _log.e('Error activating layer $id: $e');
    }
  }

  /// Removes a navigation layer by its identifier and reactivates the new top layer.
  static void popLayer(String id) {
    if (_stack.isEmpty) return;

    _log.i('[GamepadNavigationManager] Popping layer: $id');

    final index = _stack.indexWhere((layer) => layer.id == id);
    if (index == -1) {
      _log.w('[GamepadNavigationManager] Layer $id not found in stack');
      return;
    }

    final isTop = index == _stack.length - 1;
    final layer = _stack.removeAt(index);

    if (isTop) {
      try {
        layer.onDeactivate();
      } catch (e) {
        _log.e('Error deactivating layer $id during pop: $e');
      }

      if (_stack.isNotEmpty) {
        _log.i(
          '[GamepadNavigationManager] Reactivating previous layer: ${_stack.last.id}',
        );
        try {
          _stack.last.onActivate();
        } catch (e) {
          _log.e('Error reactivating layer ${_stack.last.id}: $e');
        }
      }
    }
  }

  /// Deactivates all layers in the stack.
  ///
  /// Typically called when launching a game to prevent UI interaction during gameplay.
  static void deactivateAll() {
    if (_stack.isNotEmpty) {
      _log.i('[GamepadNavigationManager] Deactivating all layers');
      try {
        _stack.last.onDeactivate();
      } catch (e) {
        _log.e('Error deactivating top layer: $e');
      }
    }
  }

  /// Reactivates the topmost layer in the stack.
  static void reactivate() {
    if (_stack.isNotEmpty) {
      _log.i(
        '[GamepadNavigationManager] Reactivating top layer: ${_stack.last.id}',
      );
      try {
        _stack.last.onActivate();
      } catch (e) {
        _log.e('Error reactivating top layer: $e');
      }
    }
  }

  /// Removes every layer above [id] and reactivates [id].
  ///
  /// Used when a dialog must reclaim focus after an async action (e.g. changing
  /// a view mode) caused background widgets to push their own layers on top.
  static void popLayersAbove(String id) {
    final index = _stack.indexWhere((layer) => layer.id == id);
    if (index == -1) {
      _log.w(
        '[GamepadNavigationManager] Layer $id not found for popLayersAbove',
      );
      return;
    }

    while (_stack.length > index + 1) {
      final layer = _stack.removeLast();
      _log.i('[GamepadNavigationManager] popLayersAbove: removing ${layer.id}');
      try {
        layer.onDeactivate();
      } catch (e) {
        _log.e('Error deactivating layer ${layer.id}: $e');
      }
    }

    if (_stack.isNotEmpty) {
      _log.i(
        '[GamepadNavigationManager] popLayersAbove: reactivating ${_stack.last.id}',
      );
      try {
        _stack.last.onActivate();
      } catch (e) {
        _log.e('Error reactivating layer ${_stack.last.id}: $e');
      }
    }
  }
}
