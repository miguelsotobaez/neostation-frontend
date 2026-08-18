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

  /// Ensures the item at [index] is visible, given the per-item [keys] and the
  /// list's [controller].
  ///
  /// Prefer this over [ensureVisible] for list/grid panels: a lazy list
  /// (`ListView.builder`) only mounts what is on screen, so an item scrolled
  /// far out of view has no context and [ensureVisible] would silently do
  /// nothing — which is what happens when focus re-enters a panel at index 0
  /// from far down the list. The top of the list is unambiguous without a
  /// context, so it falls back to [controller]; any other unmounted index is
  /// left alone rather than guessed at from an estimated row height.
  void ensureVisibleIndex(
    int index, {
    required List<GlobalKey> keys,
    ScrollController? controller,
  }) {
    if (index < 0 || index >= keys.length) return;

    final ctx = keys[index].currentContext;
    if (ctx != null) {
      ensureVisible(ctx);
      return;
    }

    if (index == 0 && (controller?.hasClients ?? false)) {
      controller!.jumpTo(0);
    }
  }

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
