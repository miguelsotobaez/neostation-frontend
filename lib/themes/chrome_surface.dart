import 'dart:ui';

import 'package:flutter/material.dart';

/// Translucency tokens for NeoStation's floating chrome.
///
/// The game views render every control over the selected game's fanart: the
/// list sidebar, the action rail, the header toolbar, the footer pills and the
/// alphabet indicator all sit on top of artwork. They share one visual role —
/// a `surface` fill let down far enough for the artwork to read through — and
/// before this extension existed each one hardcoded its own alpha, so the set
/// drifted apart (the toolbar was fully opaque while its neighbours were at
/// 0.9).
///
/// Everything in that role now derives from these four values, so the whole
/// chrome moves together and a future user-facing opacity setting has a single
/// knob to turn.
///
/// Two shapes are offered:
/// - [fill] — flat translucency, for pills and toolbars. Their text spans the
///   whole element, so there is no edge to hide a fade in.
/// - [fade]/[fadeNarrow] — a left-to-right falloff for large panels, which
///   keeps the leading edge legible where content sits and lets the artwork
///   bleed through at the trailing edge, so the panel reads as a pane laid over
///   the fanart rather than a block cut out of it.
///
/// Modal dialogs deliberately do *not* use these tokens: they sit over a scrim
/// rather than over artwork, and want their own (higher) opacity.
@immutable
class ChromeSurface extends ThemeExtension<ChromeSurface> {
  /// Flat chrome: pills, the header toolbar, the letter indicator.
  final double opacity;

  /// Leading-edge opacity of a faded panel.
  final double fadeLeading;

  /// Trailing-edge opacity of a wide faded panel (the game list sidebar).
  final double fadeTrailing;

  /// Trailing-edge opacity of a narrow faded panel (the action rail). Gentler
  /// than [fadeTrailing]: the rail is one icon wide, so its content runs edge
  /// to edge and there is no opaque zone to hide it in.
  final double fadeTrailingNarrow;

  const ChromeSurface({
    required this.opacity,
    required this.fadeLeading,
    required this.fadeTrailing,
    required this.fadeTrailingNarrow,
  });

  /// The values every theme ships with today. Override per theme later.
  factory ChromeSurface.standard() {
    return const ChromeSurface(
      opacity: 0.75,
      fadeLeading: 0.78,
      fadeTrailing: 0.38,
      fadeTrailingNarrow: 0.48,
    );
  }

  static ChromeSurface _of(ThemeData theme) {
    final chrome = theme.extension<ChromeSurface>();
    assert(chrome != null, 'ChromeSurface extension is missing from the theme');
    return chrome ?? ChromeSurface.standard();
  }

  static ChromeSurface of(BuildContext context) => _of(Theme.of(context));

  /// Flat chrome fill for pills, toolbars and the letter indicator.
  static Color fill(BuildContext context) {
    final theme = Theme.of(context);
    return theme.colorScheme.surface.withValues(alpha: _of(theme).opacity);
  }

  /// Left-to-right falloff for a wide chrome panel (the game list sidebar).
  static LinearGradient fade(BuildContext context) {
    final theme = Theme.of(context);
    return _of(theme)._gradient(theme, _of(theme).fadeTrailing);
  }

  /// Left-to-right falloff for a narrow chrome panel (the action rail), so it
  /// reads as one lit surface with the sidebar beside it.
  static LinearGradient fadeNarrow(BuildContext context) {
    final theme = Theme.of(context);
    return _of(theme)._gradient(theme, _of(theme).fadeTrailingNarrow);
  }

  LinearGradient _gradient(ThemeData theme, double trailing) {
    final surface = theme.colorScheme.surface;
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        surface.withValues(alpha: fadeLeading),
        surface.withValues(alpha: trailing),
      ],
    );
  }

  @override
  ChromeSurface copyWith({
    double? opacity,
    double? fadeLeading,
    double? fadeTrailing,
    double? fadeTrailingNarrow,
  }) {
    return ChromeSurface(
      opacity: opacity ?? this.opacity,
      fadeLeading: fadeLeading ?? this.fadeLeading,
      fadeTrailing: fadeTrailing ?? this.fadeTrailing,
      fadeTrailingNarrow: fadeTrailingNarrow ?? this.fadeTrailingNarrow,
    );
  }

  @override
  ChromeSurface lerp(ChromeSurface? other, double t) {
    if (other == null) return this;
    return ChromeSurface(
      opacity: lerpDouble(opacity, other.opacity, t)!,
      fadeLeading: lerpDouble(fadeLeading, other.fadeLeading, t)!,
      fadeTrailing: lerpDouble(fadeTrailing, other.fadeTrailing, t)!,
      fadeTrailingNarrow: lerpDouble(
        fadeTrailingNarrow,
        other.fadeTrailingNarrow,
        t,
      )!,
    );
  }
}
