import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// A D-pad left/right glyph lifted off the background by a soft halo.
///
/// The companion to [BumperGlyph] for screens that drive tabs from the D-pad
/// instead of the shoulders. It follows the same treatment: tinted
/// [ColorScheme.onSurface] and drawn outside the tab pill, directly over
/// whatever fanart sits behind the chrome, with a single blurred copy of the
/// glyph behind it for separation.
///
/// No filled backing variant is needed here. The bumper asset knocks its
/// "LB"/"RB" lettering out to transparent and needs a solid copy underneath so
/// the letters do not read as holes; the D-pad asset is an outlined cross with
/// the pressed arm filled, so its transparent centre is meant to show through.
class DpadGlyph extends StatelessWidget {
  final bool isLeft;
  final double? size;

  const DpadGlyph({super.key, required this.isLeft, this.size});

  /// Strength of the halo. Low enough to stay a hint rather than a shadow.
  static const double _haloAlpha = 0.5;

  /// Blur sigma, in logical pixels before screenutil scaling.
  static const double _haloBlur = 1.5;

  @override
  Widget build(BuildContext context) {
    final double dimension = size ?? 22.r;
    final scheme = Theme.of(context).colorScheme;
    final String asset = isLeft
        ? 'assets/images/gamepad/Xbox_D-pad_L.png'
        : 'assets/images/gamepad/Xbox_D-pad_R.png';

    Widget copy(Color color) =>
        Image.asset(asset, width: dimension, height: dimension, color: color);

    return SizedBox(
      width: dimension,
      height: dimension,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(
              sigmaX: _haloBlur.r,
              sigmaY: _haloBlur.r,
            ),
            child: copy(scheme.surface.withValues(alpha: _haloAlpha)),
          ),
          copy(scheme.onSurface),
        ],
      ),
    );
  }
}
