import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'shimmering_logo.dart';

/// Shared chrome for the intro screens: the shimmering logo pinned at the
/// screen centre with a status block hung directly underneath it.
///
/// The logo stays at the exact centre — the same spot the native splash icon
/// occupies — so it never moves across the native → startup → scan handoff.
///
/// The status block is placed from the logo's *rendered* bottom edge rather
/// than at a fixed fraction of the screen height. A fraction only clears the
/// logo on a screen tall enough for it: on short panels half the fixed-size
/// logo is taller than the offset, which is how the loading text and the scan
/// progress bar ended up printed across the glyph. For the same reason the
/// logo is scaled down once it would take more than [_maxLogoHeightFraction]
/// of the screen, which is what guarantees room for the status block below it.
class SplashStatusLayout extends StatelessWidget {
  const SplashStatusLayout({super.key, required this.children, this.progress});

  /// Status widgets stacked under the logo (progress bar, status line, …).
  final List<Widget> children;

  /// Forwarded to [ShimmeringLogo]. Null keeps the ambient sweep.
  final double? progress;

  /// Rendered logo width on a screen with room for it. Matches what the
  /// startup and scan splashes used before the layout was made responsive,
  /// so nothing moves on the devices that were already laying out correctly.
  static const double _maxLogoWidth = 280;

  /// Aspect ratio of `assets/images/logo_transparent.png` (772×510).
  static const double _logoAspect = 772 / 510;

  /// Share of the screen width the logo may take, so it stays a logo rather
  /// than a wall on narrow panels.
  static const double _maxLogoWidthFraction = 0.55;

  /// Share of the screen height the logo may take before it is scaled down.
  /// Chosen so the Thor's ~467dp-tall screen still renders the logo at its
  /// full [_maxLogoWidth] — only panels shorter than that scale it back.
  static const double _maxLogoHeightFraction = 0.40;

  /// Clear space between the logo's bottom edge and the status block.
  static const double _gap = 16;

  /// Keeps the status text off the very bottom edge of the panel.
  static const double _bottomInset = 12;

  /// Horizontal breathing room, and the width past which centred status text
  /// starts reading as a paragraph instead of a caption.
  static const double _horizontalPadding = 32;
  static const double _maxStatusWidth = 480;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Fall back to the design size when handed an unbounded axis; the
        // splash is always full-screen in practice, but an infinite extent
        // would otherwise produce a NaN offset.
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : _maxLogoWidth / _maxLogoWidthFraction;
        final height = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : _maxLogoWidth / _logoAspect / _maxLogoHeightFraction;

        final logoWidth = math.min(
          _maxLogoWidth,
          math.min(
            width * _maxLogoWidthFraction,
            height * _maxLogoHeightFraction * _logoAspect,
          ),
        );
        final logoHeight = logoWidth / _logoAspect;

        final statusWidth = math.max(
          0.0,
          math.min(_maxStatusWidth, width) - _horizontalPadding * 2,
        );

        return Stack(
          children: [
            Center(
              child: ShimmeringLogo(width: logoWidth, progress: progress),
            ),
            Positioned(
              top: height / 2 + logoHeight / 2 + _gap,
              left: 0,
              right: 0,
              bottom: _bottomInset,
              // The status text is laid out at its natural size and only
              // scaled down when the panel is too short to hold it — a long
              // status that wraps to three lines shrinks to fit rather than
              // running off the bottom edge. On a panel with room the scale
              // is 1 and nothing changes.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: statusWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
