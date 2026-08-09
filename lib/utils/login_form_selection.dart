import 'package:flutter/material.dart';

/// Gamepad cursor state shared by the app's login forms.
///
/// Every login form is the same shape: an ordered list of slots the D-pad
/// walks, where each slot is either a text field to focus or a control to
/// activate, driven by Up/Down and A.
///
/// The slot list is read fresh each time rather than captured, so forms whose
/// fields change with their mode — register showing a username the login state
/// doesn't, a verification step replacing both — describe the current state and
/// nothing here has to be told it changed.
mixin LoginFormSelection<T extends StatefulWidget> on State<T> {
  /// The form's selectable slots in cursor order. A null entry is an action
  /// control (a button) rather than a text field.
  List<FocusNode?> get selectionSlots;

  /// Every focus node the form owns, including any absent from the current
  /// [selectionSlots]. Forms whose slot list varies must widen this so focus
  /// tracking survives a mode switch; a fixed form can leave it alone.
  List<FocusNode> get ownedFocusNodes =>
      selectionSlots.whereType<FocusNode>().toList();

  final List<VoidCallback> _focusListeners = [];
  List<FocusNode> _listenedNodes = const [];

  int _selectedSlot = 0;

  /// Total selectable slots in the form's current state.
  int get slotCount => selectionSlots.length;

  /// Slot the gamepad cursor is on.
  ///
  /// Clamped on read so a mode switch that shortens the form can never leave
  /// the cursor pointing past the end of the new slot list.
  int get selectedSlot {
    final count = slotCount;
    if (count == 0) return 0;
    return _selectedSlot.clamp(0, count - 1);
  }

  /// The form's last slot, which on a simple form is its submit button. Forms
  /// with several action controls should name their slots explicitly instead.
  int get submitSlot => slotCount == 0 ? 0 : slotCount - 1;

  bool isSelected(int slot) => selectedSlot == slot;

  /// The focus node under the cursor, or null when it is on a control.
  FocusNode? get selectedFocusNode {
    final slots = selectionSlots;
    return slots.isEmpty ? null : slots[selectedSlot];
  }

  bool isAnyFieldFocused() => ownedFocusNodes.any((node) => node.hasFocus);

  /// Focuses the selected slot when it is a text field.
  ///
  /// Returns false when the cursor is on an action control, which is the
  /// screen's cue to run whatever that control does.
  bool focusSelectedField() {
    final node = selectedFocusNode;
    if (node == null) return false;
    node.requestFocus();
    return true;
  }

  /// Drops focus (and the soft keyboard) so the D-pad can move again. B is the
  /// app-wide way out of a focused text field.
  void exitTextEntry() {
    if (isAnyFieldFocused()) FocusScope.of(context).unfocus();
  }

  /// Moves the cursor by [delta], wrapping around the form.
  ///
  /// Refuses while a text field has focus so the highlight can't drift away
  /// from where typing actually lands — on a desktop gamepad the directional
  /// event reaches this layer even though the keystrokes go to the field.
  ///
  /// Returns whether the cursor moved, which drives the nav sound.
  bool moveSelection(int delta) {
    if (isAnyFieldFocused()) return false;
    final count = slotCount;
    if (count == 0) return false;
    setState(() {
      _selectedSlot = (selectedSlot + delta + count) % count;
    });
    return true;
  }

  /// Puts the cursor back on the first slot, e.g. after logging out or on a
  /// switch to a different form mode.
  void resetSelection() {
    if (_selectedSlot == 0) return;
    setState(() => _selectedSlot = 0);
  }

  /// [resetSelection] for use inside an enclosing [setState] — typically a mode
  /// switch that is already rebuilding, where a nested setState would throw.
  void resetSelectionInPlace() => _selectedSlot = 0;

  /// Keeps the highlight on whichever field the platform focused.
  ///
  /// [moveSelection] is not the only thing that moves focus: the IME "next"
  /// action jumps field to field via `onFieldSubmitted`, and a tap or click
  /// focuses a field directly. Without this the highlight and the real focus
  /// disagree, and a later A fires whatever the stale highlight landed on.
  ///
  /// Call from `initState`, and [detachFocusSelectionListeners] from `dispose`.
  void attachFocusSelectionListeners() {
    detachFocusSelectionListeners();
    _listenedNodes = List.of(ownedFocusNodes);
    for (final node in _listenedNodes) {
      void listener() {
        if (!node.hasFocus || !mounted) return;
        // Resolved against the live slot list: a node's slot moves when the
        // form does, and a node absent from the current state has none.
        final slot = selectionSlots.indexOf(node);
        if (slot < 0 || _selectedSlot == slot) return;
        setState(() => _selectedSlot = slot);
      }

      node.addListener(listener);
      _focusListeners.add(listener);
    }
  }

  void detachFocusSelectionListeners() {
    for (var i = 0; i < _focusListeners.length; i++) {
      _listenedNodes[i].removeListener(_focusListeners[i]);
    }
    _focusListeners.clear();
    _listenedNodes = const [];
  }
}
