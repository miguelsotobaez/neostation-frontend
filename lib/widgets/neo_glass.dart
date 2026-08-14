import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// A performant, dependency-free frosted-glass surface.
///
/// It replicates the cheap "frosted" path of the liquid-glass packages we
/// evaluated: a single engine [BackdropFilter] blur pass over a translucent
/// tint, clipped to the panel's own shape, with a canvas-drawn specular rim.
///
/// Deliberately does NOT do the expensive parts of a full liquid-glass
/// package — refraction, distortion, chromatic aberration and the shader that
/// re-samples the live backdrop every frame. Those shader passes are what made
/// the previous dependency heavy on low-end GPUs (Android TV included). The
/// engine blur is optimized and clipped to the small panel area, so this stays
/// cheap even when the content behind the glass changes every frame.
///
/// Structure is intentionally flat: the frosted surface is one clipped node
/// and the rim is a single [CustomPaint] foreground pass on top of it — no
/// stacked sibling layer, no per-pass painters.
class NeoGlass extends StatelessWidget {
  const NeoGlass({
    super.key,
    required this.child,
    this.cornerRadius = 14,
    this.blur = 2,
    this.tint,
    this.padding,
    this.rimIntensity = 1,
  });

  final Widget child;

  /// Corner radius of the glass panel.
  final double cornerRadius;

  /// Gaussian blur sigma applied to the backdrop.
  ///
  /// `0` disables the blur entirely — the surface becomes a flat translucent
  /// panel (the cheapest mode, zero backdrop cost). Keep it modest on low-end
  /// GPUs; the cost scales with the blurred area.
  final double blur;

  /// Translucent fill tinted over the blurred backdrop. Defaults to a
  /// scaffold-background tint.
  final Color? tint;

  /// Inset applied inside the glass around [child].
  final EdgeInsetsGeometry? padding;

  /// Strength of the specular rim highlight (0.0–1.0). The rim blends with the
  /// image behind the glass, so it appears as the backdrop colour lifted
  /// brighter.
  final double rimIntensity;

  @override
  Widget build(BuildContext context) {
    // Semi-transparent so the image behind shows through and the rim (drawn
    // beneath it) glows with the backdrop's colours.
    final glassTint =
        tint ??
        Theme.of(context).scaffoldBackgroundColor.withValues(alpha: 0.8);

    Widget surface = ColoredBox(
      color: glassTint,
      child: padding != null ? Padding(padding: padding!, child: child) : child,
    );

    // One engine blur pass over the backdrop, clipped to the panel shape.
    // This is the whole "frost" — no refraction shader, no per-frame capture.
    if (blur > 0) {
      surface = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: surface,
      );
    }

    return CustomPaint(
      foregroundPainter: rimIntensity > 0
          ? _GlassRimPainter(
              cornerRadius: cornerRadius,
              intensity: rimIntensity,
            )
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(cornerRadius),
        child: surface,
      ),
    );
  }
}

/// Paints the glass rim: a soft specular highlight sweeping with the light
/// direction, matching how the liquid-glass packages shade their borders — but
/// in a single plain-Canvas stroke blended over the backdrop.
class _GlassRimPainter extends CustomPainter {
  _GlassRimPainter({required this.cornerRadius, required this.intensity})
    : _colors = [
        Colors.white.withValues(alpha: 0.96 * intensity),
        Colors.white.withValues(alpha: 0.64 * intensity),
        Colors.white.withValues(alpha: 0.16 * intensity),
      ];

  final double cornerRadius;
  final double intensity;

  // Precomputed, size-independent gradient stops (alpha depends only on
  // [intensity]); the shader itself is built per paint from the panel size.
  final List<Color> _colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;

    // Rounded-rect outline offset OUTWARD by half the stroke width, so the
    // border sits outside the card's edge (external, not inset/middle) and
    // blends with the backdrop image behind the card.
    final strokeWidth = 2.h;
    final extent = strokeWidth / 2;
    final rect = (Offset.zero & size).inflate(extent);
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius + extent)),
      );

    // Light from the top-left. The rim stays light all around — it only fades
    // in strength towards the far edge, it never turns dark. Blended with
    // BlendMode.overlay so the edge reads as the backdrop colour lifted
    // brighter (overlay preserves the hue instead of washing it to white).
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..isAntiAlias = true
        ..blendMode = BlendMode.overlay
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _colors,
          stops: const [0.0, 0.60, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_GlassRimPainter oldDelegate) =>
      oldDelegate.cornerRadius != cornerRadius ||
      oldDelegate.intensity != intensity;
}
