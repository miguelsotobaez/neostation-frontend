import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The few colors the pre-database startup screens paint with.
///
/// The selected theme lives in SQLite, which on a cold boot may sit on storage
/// that has not mounted yet — that is precisely what the startup screens are
/// waiting for. So the resolved palette is mirrored into SharedPreferences
/// (always-available internal storage) whenever the theme changes, and read
/// back from there on the next launch.
@immutable
class StartupThemeColors {
  const StartupThemeColors({
    required this.background,
    required this.foreground,
    required this.primary,
  });

  /// Surface the startup screens fill.
  final Color background;

  /// Text/icon color used on [background].
  final Color foreground;

  /// Accent used for the error screen's buttons.
  final Color primary;

  /// Dark neostation chrome — what a first launch (empty cache) paints, and
  /// the fallback whenever the cache cannot be read. Values mirror
  /// `dark_theme.dart` so a default install shows no handoff at all.
  static const fallback = StartupThemeColors(
    background: Color(0xFF15191e),
    foreground: Color(0xFFecf9ff),
    primary: Color(0xFF605dff),
  );

  /// Derived from the painted background rather than the theme's own
  /// brightness flag: custom (imported) themes can pair either one, and it is
  /// the background that decides whether Material's defaults will be legible.
  Brightness get brightness =>
      background.computeLuminance() > 0.5 ? Brightness.light : Brightness.dark;

  /// Minimal theme for the startup screens, so the storage-error screen's
  /// buttons pick up the user's accent instead of Material's stock purple.
  ThemeData get themeData => ThemeData(
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ),
  );
}

/// Persists [StartupThemeColors] across launches.
class StartupThemeCache {
  const StartupThemeCache._();

  static const _backgroundKey = 'startup_theme_background';
  static const _foregroundKey = 'startup_theme_foreground';
  static const _primaryKey = 'startup_theme_primary';

  /// Reads the cached palette, falling back to the dark chrome when nothing
  /// has been cached yet (first launch) or the read fails.
  static Future<StartupThemeColors> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final background = prefs.getInt(_backgroundKey);
      final foreground = prefs.getInt(_foregroundKey);
      final primary = prefs.getInt(_primaryKey);
      if (background == null || foreground == null || primary == null) {
        return StartupThemeColors.fallback;
      }
      return StartupThemeColors(
        background: Color(background),
        foreground: Color(foreground),
        primary: Color(primary),
      );
    } catch (_) {
      return StartupThemeColors.fallback;
    }
  }

  /// Mirrors [theme]'s startup-relevant colors for the next launch. Failures
  /// are swallowed: a stale cache only costs a brief mismatched startup
  /// screen, and this runs on the theme-change path where nothing should throw.
  static Future<void> save(ThemeData theme) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        _backgroundKey,
        theme.scaffoldBackgroundColor.toARGB32(),
      );
      await prefs.setInt(
        _foregroundKey,
        theme.colorScheme.onSurface.toARGB32(),
      );
      await prefs.setInt(_primaryKey, theme.colorScheme.primary.toARGB32());
    } catch (_) {
      // Ignored — see doc comment.
    }
  }
}
