import 'package:flutter/material.dart';

/// Detects a deliberate horizontal swipe on [child] and fires [onSwipeLeft] /
/// [onSwipeRight]. Triggers on EITHER a short travel distance OR a fast fling,
/// so a slow drag works as well as a quick flick (velocity-only detection feels
/// stiff — the user has to flick fast for it to register).
class HorizontalSwipe extends StatefulWidget {
  final Widget child;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;
  final HitTestBehavior behavior;

  /// Travel past this many logical px (in one direction) fires regardless of
  /// speed.
  final double distanceThreshold;

  /// Fling faster than this (logical px/s) fires even on a short travel.
  final double velocityThreshold;

  const HorizontalSwipe({
    super.key,
    required this.child,
    this.onSwipeLeft,
    this.onSwipeRight,
    this.behavior = HitTestBehavior.opaque,
    this.distanceThreshold = 36.0,
    this.velocityThreshold = 120.0,
  });

  @override
  State<HorizontalSwipe> createState() => _HorizontalSwipeState();
}

class _HorizontalSwipeState extends State<HorizontalSwipe> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onHorizontalDragStart: (_) => _dx = 0,
      onHorizontalDragUpdate: (d) => _dx += d.delta.dx,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        final left =
            _dx <= -widget.distanceThreshold || v <= -widget.velocityThreshold;
        final right =
            _dx >= widget.distanceThreshold || v >= widget.velocityThreshold;
        if (left) {
          widget.onSwipeLeft?.call();
        } else if (right) {
          widget.onSwipeRight?.call();
        }
      },
      child: widget.child,
    );
  }
}
