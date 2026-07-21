import 'package:flutter/foundation.dart';

/// Session-scoped visibility of the vertical action-button legend, shared across
/// all game views (list, grid, carousel). Toggled by the Select + B chord.
///
/// In-memory only for now, so it resets each launch; a persisted user-config
/// entry will back this later. Views listen to [hidden] so a toggle in one view
/// is reflected when any other view is next shown within the session.
class GameLegendVisibility {
  GameLegendVisibility._();

  /// True when the legend is hidden across every game view.
  static final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);

  static void toggle() => hidden.value = !hidden.value;
}
