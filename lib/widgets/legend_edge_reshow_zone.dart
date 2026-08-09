import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../services/game_legend_visibility.dart';
import 'horizontal_swipe.dart';

/// Invisible left-edge gesture strip that reveals the action-button legend on a
/// swipe-right, for touchscreen users who hid it with a swipe-left (the legend
/// itself is off-screen when hidden, so the reshow affordance has to live here).
///
/// Place it as a direct child of the game view's [Stack]. It only claims a hit
/// region while the legend is hidden; otherwise it collapses to nothing so it
/// never intercepts taps on the visible legend or the content behind it.
class LegendEdgeReshowZone extends StatelessWidget {
  const LegendEdgeReshowZone({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: GameLegendVisibility.hidden,
      builder: (context, hidden, _) {
        if (!hidden) return const SizedBox.shrink();
        return Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          width: 28.r,
          child: HorizontalSwipe(
            behavior: HitTestBehavior.translucent,
            onSwipeRight: GameLegendVisibility.show,
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}
