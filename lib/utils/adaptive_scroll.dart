import 'package:flutter/widgets.dart';

/// Scrolls a focused item into view, adapting the animation to how fast the
/// user is navigating.
///
/// Gamepad/D-pad menus fire one scroll per selection change. Animating every
/// one (e.g. 200ms easeInOut) makes the viewport visibly lag behind the cursor
/// when the user scrolls quickly, because each keypress starts a fresh
/// animation that never has time to finish. This helper tracks the interval
/// between calls: when moves arrive rapidly it snaps instantly so the focused
/// item is always on screen, and only animates when the user has paused.
class AdaptiveScroller {
  AdaptiveScroller({
    this.rapidThreshold = const Duration(milliseconds: 180),
    this.animationDuration = const Duration(milliseconds: 200),
    this.curve = Curves.easeInOut,
    this.alignment = 0.5,
  });

  /// Moves closer together than this snap instantly instead of animating.
  final Duration rapidThreshold;

  /// Animation duration used for a single, unhurried move.
  final Duration animationDuration;

  final Curve curve;

  /// Target alignment of the item within the viewport (0.5 = centered).
  final double alignment;

  DateTime? _lastScroll;

  /// Ensures [context]'s item is visible, snapping during rapid navigation.
  void ensureVisible(BuildContext context) {
    final now = DateTime.now();
    final last = _lastScroll;
    final isRapid = last != null && now.difference(last) < rapidThreshold;
    _lastScroll = now;

    Scrollable.ensureVisible(
      context,
      duration: isRapid ? Duration.zero : animationDuration,
      curve: curve,
      alignment: alignment,
    );
  }
}
