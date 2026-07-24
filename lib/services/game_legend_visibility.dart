import 'package:flutter/foundation.dart';

/// Visibility of the vertical action-button legend, shared across all game views
/// (list, grid, carousel). Toggled by the Select + B chord.
///
/// The value is persisted to `user_config.legend_hidden` so a toggle survives
/// restarts and upgrades. [bind] seeds the in-memory notifier from the loaded
/// config and wires the persistence sink once during app startup. Views listen
/// to [hidden] so a toggle in one view is reflected the next time any other view
/// is shown.
class GameLegendVisibility {
  GameLegendVisibility._();

  /// True when the legend is hidden across every game view.
  static final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);

  /// Durable sink for [hidden]. Wired once via [bind]; `null` until then, so
  /// early toggles simply stay in memory.
  static Future<void> Function(bool hidden)? _persist;

  /// Seeds [hidden] from persisted config and wires the persistence sink. Call
  /// once during startup, after the config provider has loaded.
  static void bind({
    required bool initialHidden,
    required Future<void> Function(bool hidden) persist,
  }) {
    hidden.value = initialHidden;
    _persist = persist;
  }

  static void toggle() => _set(!hidden.value);

  /// Hides the legend (e.g. swipe-left on touch). No-op if already hidden.
  static void hide() => _set(true);

  /// Reveals the legend (e.g. swipe-right from the screen edge on touch).
  /// No-op if already visible.
  static void show() => _set(false);

  static void _set(bool value) {
    if (hidden.value == value) return;
    hidden.value = value;
    _persist?.call(value);
  }
}
