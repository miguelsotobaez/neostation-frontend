import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// An LB/RB bumper glyph lifted off the background by a soft halo.
///
/// The glyphs are tinted [ColorScheme.onSurface] and are drawn outside the tab
/// pills, directly over whatever fanart is behind the chrome — without the
/// pill's backing they wash out on light artwork.
///
/// The halo is a single blurred copy of the glyph behind it, not an outline.
/// A ring of offset copies gives a crisp edge that reads as a hard chip around
/// a shape this small however far its opacity is dropped; blurring removes the
/// edge entirely, so the glyph gains separation without gaining weight.
///
/// Tune with [_haloAlpha] (how dark) and [_haloBlur] (how far it spreads).
class BumperGlyph extends StatelessWidget {
  final bool isLeft;
  final double? size;

  const BumperGlyph({super.key, required this.isLeft, this.size});

  /// Strength of the halo. Low enough to stay a hint rather than a shadow.
  static const double _haloAlpha = 0.5;

  /// Blur sigma, in logical pixels before screenutil scaling.
  static const double _haloBlur = 1.5;

  @override
  Widget build(BuildContext context) {
    final double dimension = size ?? 22.r;
    final scheme = Theme.of(context).colorScheme;
    final String asset = isLeft
        ? 'assets/images/gamepad/Xbox_LB_bumper.png'
        : 'assets/images/gamepad/Xbox_RB_bumper.png';

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
