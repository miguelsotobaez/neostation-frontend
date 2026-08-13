import 'dart:ui';

import 'package:flutter/material.dart';

/// Visual roles used by NeoStation's adaptive glass surfaces.
///
/// They intentionally describe *usage* rather than a particular theme. The
/// actual opacity and blur are derived from the active ColorScheme at runtime,
/// so built-in and imported themes get a coherent glass treatment without
/// requiring per-theme hardcoded values.
enum GlassSurfaceRole { panel, rail, modal, chrome, pill, card }

/// Translucency tokens for NeoStation's floating chrome.
///
/// The base values below are the dark-theme baseline. Light and highly
/// saturated themes are adjusted automatically at render time so contrast is
/// preserved while the fanart remains visible through the UI.
@immutable
class ChromeSurface extends ThemeExtension<ChromeSurface> {
  /// Flat chrome: pills, the header toolbar, the letter indicator.
  final double opacity;

  /// Leading-edge opacity of a faded panel.
  final double fadeLeading;

  /// Trailing-edge opacity of a wide faded panel (the game list sidebar).
  final double fadeTrailing;

  /// Trailing-edge opacity of a narrow faded panel (the action rail).
  final double fadeTrailingNarrow;

  const ChromeSurface({
    required this.opacity,
    required this.fadeLeading,
    required this.fadeTrailing,
    required this.fadeTrailingNarrow,
  });

  /// Dark-theme baseline. Light/vivid themes are boosted dynamically by the
  /// helpers below rather than maintaining a separate table for every theme.
  factory ChromeSurface.standard() {
    return const ChromeSurface(
      opacity: 0.66,
      fadeLeading: 0.58,
      fadeTrailing: 0.28,
      fadeTrailingNarrow: 0.42,
    );
  }

  static ChromeSurface _of(ThemeData theme) {
    final chrome = theme.extension<ChromeSurface>();
    assert(chrome != null, 'ChromeSurface extension is missing from the theme');
    return chrome ?? ChromeSurface.standard();
  }

  static ChromeSurface of(BuildContext context) => _of(Theme.of(context));

  static bool _isLight(ThemeData theme) {
    // Brightness is authoritative for built-in/imported themes, while the
    // luminance fallback protects custom ColorSchemes that were constructed
    // with an inconsistent brightness flag.
    return theme.brightness == Brightness.light ||
        theme.colorScheme.surface.computeLuminance() > 0.45;
  }

  static double _saturation(ThemeData theme) =>
      HSVColor.fromColor(theme.colorScheme.surface).saturation;

  /// Small opacity reinforcement for highly saturated themes. Without it a
  /// vivid blue/yellow surface mixed with a colorful fanart can become muddy
  /// much faster than a neutral dark/white surface at the same alpha.
  static double _vividBoost(ThemeData theme) {
    final saturation = _saturation(theme);
    if (saturation >= 0.70) return 0.04;
    if (saturation >= 0.45) return 0.02;
    return 0.0;
  }

  static double _adaptiveAlpha(
    ThemeData theme,
    double darkBase, {
    required double lightBoost,
    double min = 0.0,
    double max = 1.0,
  }) {
    final value = darkBase +
        (_isLight(theme) ? lightBoost : 0.0) +
        _vividBoost(theme);
    return value.clamp(min, max).toDouble();
  }

  /// Flat chrome fill for the header/footer controls. It stays a little more
  /// opaque than the large panels because icons and labels occupy the full
  /// surface and have no quiet area around them.
  static Color fill(BuildContext context) {
    final theme = Theme.of(context);
    final alpha = _adaptiveAlpha(
      theme,
      _of(theme).opacity,
      lightBoost: 0.10,
      min: 0.58,
      max: 0.82,
    );
    return theme.colorScheme.surface.withValues(alpha: alpha);
  }

  /// Tint for an actual glass surface according to its role.
  static Color glassFill(BuildContext context, GlassSurfaceRole role) {
    final theme = Theme.of(context);
    final chrome = _of(theme);

    final (darkBase, lightBoost, min, max) = switch (role) {
      GlassSurfaceRole.panel => (0.48, 0.16, 0.46, 0.72),
      GlassSurfaceRole.rail => (0.52, 0.15, 0.50, 0.74),
      GlassSurfaceRole.modal => (0.60, 0.15, 0.58, 0.80),
      GlassSurfaceRole.chrome => (chrome.opacity, 0.10, 0.58, 0.82),
      GlassSurfaceRole.pill => (0.70, 0.10, 0.66, 0.84),
      // System cards are numerous, so they stay clearer than modal surfaces.
      // Their artwork remains opaque; this tint is mainly visible in the rim,
      // inner spacing and logo footer.
      // Main-menu system cards are rendered in large numbers. Keep the tint
      // deliberately very clear; readability is provided by the artwork/logo
      // treatment and rim rather than by an opaque slab over the theme.
      GlassSurfaceRole.card => (0.18, 0.14, 0.16, 0.40),
    };

    final alpha = _adaptiveAlpha(
      theme,
      darkBase,
      lightBoost: lightBoost,
      min: min,
      max: max,
    );
    return theme.colorScheme.surface.withValues(alpha: alpha);
  }

  /// Adaptive blur. Light surfaces receive a little more diffusion because
  /// dark text is more sensitive to busy/high-contrast fanart showing through.
  static double glassBlur(BuildContext context, GlassSurfaceRole role) {
    final theme = Theme.of(context);
    final isLight = _isLight(theme);
    final vivid = _saturation(theme) >= 0.60;

    final base = switch (role) {
      GlassSurfaceRole.panel => isLight ? 3.6 : 2.4,
      GlassSurfaceRole.rail => isLight ? 3.2 : 2.2,
      GlassSurfaceRole.modal => isLight ? 4.0 : 3.0,
      GlassSurfaceRole.chrome => isLight ? 3.2 : 2.4,
      GlassSurfaceRole.pill => isLight ? 3.0 : 2.2,
      // Keep card blur intentionally lightweight: a systems grid can render
      // many cards at once on iPhone.
      // Cards opt out of BackdropFilter in SystemCard for performance. This
      // value remains as a safe fallback for any future isolated card usage.
      GlassSurfaceRole.card => isLight ? 1.2 : 0.8,
    };

    return base + (vivid ? 0.4 : 0.0);
  }

  /// Theme-aware rim that remains visible on both very dark OLED surfaces and
  /// very bright themes without forcing a fixed white border.
  static Color glassRim(BuildContext context, GlassSurfaceRole role) {
    final theme = Theme.of(context);
    final isLight = _isLight(theme);
    final mix = Color.lerp(
          theme.colorScheme.outline,
          theme.colorScheme.onSurface,
          isLight ? 0.16 : 0.28,
        ) ??
        theme.colorScheme.outline;

    final alpha = switch (role) {
      GlassSurfaceRole.modal => isLight ? 0.34 : 0.30,
      GlassSurfaceRole.panel => isLight ? 0.30 : 0.26,
      GlassSurfaceRole.rail => isLight ? 0.32 : 0.28,
      GlassSurfaceRole.chrome => isLight ? 0.28 : 0.24,
      GlassSurfaceRole.pill => isLight ? 0.26 : 0.22,
      GlassSurfaceRole.card => isLight ? 0.24 : 0.20,
    };

    return mix.withValues(alpha: alpha);
  }

  /// Very subtle diagonal sheen. It uses onSurface rather than a fixed white
  /// so bright themes receive a dark/neutral highlight instead of a white haze.
  static LinearGradient glassSheen(
    BuildContext context,
    GlassSurfaceRole role,
  ) {
    final theme = Theme.of(context);
    final sheenAlpha = role == GlassSurfaceRole.card
        ? (_isLight(theme) ? 0.018 : 0.024)
        : (_isLight(theme) ? 0.035 : 0.055);
    final primaryAlpha = switch (role) {
      GlassSurfaceRole.modal => 0.025,
      GlassSurfaceRole.card => 0.008,
      _ => 0.018,
    };

    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        theme.colorScheme.onSurface.withValues(alpha: sheenAlpha),
        Colors.transparent,
        theme.colorScheme.primary.withValues(alpha: primaryAlpha),
      ],
      stops: const [0.0, 0.48, 1.0],
    );
  }

  /// Left-to-right falloff for a wide chrome panel (the game list sidebar).
  static LinearGradient fade(BuildContext context) {
    final theme = Theme.of(context);
    final chrome = _of(theme);
    final leading = _adaptiveAlpha(
      theme,
      chrome.fadeLeading,
      lightBoost: 0.14,
      min: 0.54,
      max: 0.78,
    );
    final trailing = _adaptiveAlpha(
      theme,
      chrome.fadeTrailing,
      lightBoost: 0.18,
      min: 0.24,
      max: 0.58,
    );
    return _gradient(theme, leading, trailing);
  }

  /// Left-to-right falloff for a narrow chrome panel (the action rail).
  static LinearGradient fadeNarrow(BuildContext context) {
    final theme = Theme.of(context);
    final chrome = _of(theme);
    final leading = _adaptiveAlpha(
      theme,
      chrome.fadeLeading,
      lightBoost: 0.14,
      min: 0.54,
      max: 0.78,
    );
    final trailing = _adaptiveAlpha(
      theme,
      chrome.fadeTrailingNarrow,
      lightBoost: 0.16,
      min: 0.38,
      max: 0.70,
    );
    return _gradient(theme, leading, trailing);
  }

  static LinearGradient _gradient(
    ThemeData theme,
    double leading,
    double trailing,
  ) {
    final surface = theme.colorScheme.surface;
    return LinearGradient(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
      colors: [
        surface.withValues(alpha: leading),
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
