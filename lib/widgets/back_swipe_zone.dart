import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../utils/gamepad_nav.dart';

/// Invisible left-edge strip that goes back on a swipe-right — the touch
/// equivalent of the B button, app-wide.
///
/// Mounted once, over the whole app (see `MaterialApp.builder` in main.dart),
/// rather than per screen. It fires [GamepadNavigation.triggerBack], which
/// dispatches to the *active* navigation layer's own back action, so the
/// gesture works on exactly the screens and dialogs where B works and means
/// there whatever B means. A layer with no back action swallows nothing: the
/// call reports false and the swipe is a no-op.
///
/// It exists because most screens carry no on-screen back control: B is a
/// gamepad button and Android's system back is a platform gesture the app does
/// not own, so a bare touchscreen (the Steam Deck's, a desktop touch monitor)
/// has neither.
///
/// Deliberately a narrow edge strip rather than a whole-screen gesture: the
/// games carousel and the systems carousel both page on a horizontal drag, and
/// a full-width back swipe would fight them. Where Android's own gesture
/// navigation claims the same edge, that system gesture wins and pops the
/// route anyway — the same outcome.
class BackSwipeZone extends StatefulWidget {
  const BackSwipeZone({super.key});

  /// Travel past this many logical px fires regardless of speed; a fling
  /// faster than [_velocityThreshold] fires even on a short travel. Both
  /// inherited from the swipe-to-hide gesture the action rail used to carry,
  /// where velocity-only detection was found to feel stiff.
  ///
  /// Measured from touch-down, not from where the recognizer claimed the drag
  /// — see [DragStartBehavior.down] below. Under the default behaviour the
  /// first [kTouchSlop] (18) px of travel are spent winning the gesture arena
  /// and never reach [_dx], so this threshold silently meant ~54 px of thumb
  /// travel starting inside a [_zoneWidth] strip. That is a long drag on a
  /// handheld, and a long drag is a late finger-lift, which is what the
  /// gesture felt like waiting for.
  static const double _distanceThreshold = 36.0;
  static const double _velocityThreshold = 120.0;

  /// Width of the hit strip. Wide enough to catch a thumb starting at the
  /// bezel, narrow enough to leave a carousel its drag area.
  static const double _zoneWidth = 32.0;

  @override
  State<BackSwipeZone> createState() => _BackSwipeZoneState();
}

class _BackSwipeZoneState extends State<BackSwipeZone> {
  double _dx = 0;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      width: BackSwipeZone._zoneWidth.r,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        // Count the travel from where the finger landed, so the slop spent
        // claiming the drag is not paid for a second time by the threshold.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) => _dx = 0,
        onHorizontalDragUpdate: (d) => _dx += d.delta.dx,
        onHorizontalDragEnd: (d) {
          final velocity = d.primaryVelocity ?? 0;
          if (_dx >= BackSwipeZone._distanceThreshold ||
              velocity >= BackSwipeZone._velocityThreshold) {
            // Plays the back sound itself only when a layer actually handles
            // it, so a swipe on a screen with nothing to go back to is silent.
            GamepadNavigation.triggerBack();
          }
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}
