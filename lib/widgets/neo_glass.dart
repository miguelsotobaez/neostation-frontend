import 'dart:ui';

import 'package:flutter/material.dart';

import '../themes/chrome_surface.dart';

/// Lightweight theme-adaptive glass container.
///
/// One BackdropFilter is used per surface; no fragment shader or extra blur
/// pass is involved. Opacity, blur and rim are resolved from the active theme
/// at runtime, including imported/custom themes.
class NeoGlass extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final GlassSurfaceRole role;
  final Gradient? gradient;
  final EdgeInsetsGeometry? padding;
  final List<BoxShadow>? boxShadow;
  final double borderWidth;

  /// Disables the BackdropFilter for surfaces rendered many times at once
  /// (for example the systems grid). Transparency + rim still provide the
  /// glass appearance without forcing a separate blur pass per item.
  final bool enableBackdropBlur;

  /// The diagonal sheen is intentionally optional on dense grids. Large chrome
  /// surfaces keep it by default.
  final bool showSheen;

  const NeoGlass({
    super.key,
    required this.child,
    required this.borderRadius,
    this.role = GlassSurfaceRole.panel,
    this.gradient,
    this.padding,
    this.boxShadow,
    this.borderWidth = 1.0,
    this.enableBackdropBlur = true,
    this.showSheen = true,
  });

  @override
  Widget build(BuildContext context) {
    final blur = ChromeSurface.glassBlur(context, role);
    final fill = ChromeSurface.glassFill(context, role);
    final rim = ChromeSurface.glassRim(context, role);
    final sheen = ChromeSurface.glassSheen(context, role);

    final decorated = DecoratedBox(
      decoration: BoxDecoration(
        color: gradient == null ? fill : null,
        gradient: gradient,
        borderRadius: borderRadius,
        border: Border.all(color: rim, width: borderWidth),
      ),
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          if (showSheen)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: sheen,
                    borderRadius: borderRadius,
                  ),
                ),
              ),
            ),
          if (padding != null) Padding(padding: padding!, child: child),
          if (padding == null) child,
        ],
      ),
    );

    final glass = ClipRRect(
      borderRadius: borderRadius,
      child: enableBackdropBlur && blur > 0.01
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: decorated,
            )
          : decorated,
    );

    if (boxShadow == null || boxShadow!.isEmpty) return glass;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: boxShadow,
      ),
      child: glass,
    );
  }
}
