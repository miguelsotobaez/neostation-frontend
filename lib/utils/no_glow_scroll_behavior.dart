import 'package:flutter/material.dart';

/// Scroll behavior that removes the Android overscroll glow/stretch indicator
/// while leaving scrolling itself intact. Applied to the secondary display so a
/// stray edge drag doesn't flash white arcs at the screen border.
class NoGlowScrollBehavior extends MaterialScrollBehavior {
  const NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}
