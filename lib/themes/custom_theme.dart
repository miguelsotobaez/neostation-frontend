import 'package:flutter/material.dart';
import 'package:neostation/themes/corner_radii.dart';

/// A concrete custom-colors holder for imported (user-supplied) themes.
///
/// The 14 built-in themes each declare their own `XCustomColors` class with the
/// same getters; imported themes cannot ship a compiled class, so they use this
/// data class instead. It exposes the exact same getters the app reads via
/// [AppThemes.getCustomColors] (which returns `dynamic`), so call sites like
/// `getCustomColors(context).batteryFull` work transparently.
@immutable
class NeoCustomColors {
  final Color batteryFull;
  final Color batteryMedium;
  final Color batteryLow;
  final Color batteryPower;

  final Color errorColor;
  final Color onErrorColor;
  final Color successColor;
  final Color onSuccessColor;
  final Color infoColor;
  final Color onInfoColor;
  final Color warningColor;
  final Color onWarningColor;

  const NeoCustomColors({
    required this.batteryFull,
    required this.batteryMedium,
    required this.batteryLow,
    required this.batteryPower,
    required this.errorColor,
    required this.onErrorColor,
    required this.successColor,
    required this.onSuccessColor,
    required this.infoColor,
    required this.onInfoColor,
    required this.warningColor,
    required this.onWarningColor,
  });
}

/// A user-imported color theme, reconstructed at runtime from a daisyUI JSON
/// palette (the format exported by the NeoStation theme designer).
///
/// Built-in color themes are compiled Dart; imported ones live only as JSON on
/// disk, so this class re-derives a [ThemeData] + [NeoCustomColors] from the
/// stored palette every time it is loaded.
@immutable
class CustomTheme {
  /// Stable identifier (kebab/snake), also the on-disk file name (`<id>.json`).
  final String id;

  /// Human-readable display name shown in the theme grid.
  final String name;

  final Brightness brightness;
  final ThemeData themeData;
  final NeoCustomColors customColors;

  /// The original daisyUI JSON, kept verbatim so it can be re-persisted.
  final Map<String, dynamic> rawJson;

  const CustomTheme({
    required this.id,
    required this.name,
    required this.brightness,
    required this.themeData,
    required this.customColors,
    required this.rawJson,
  });

  /// Builds a [CustomTheme] from a daisyUI theme JSON map.
  ///
  /// Mirrors the `dartExport()` mapping in the theme designer
  /// (`~/dev/neostation-theme-designer/index.html`) so an imported theme looks
  /// identical to the designer's live preview.
  ///
  /// Throws [FormatException] when required keys are missing or malformed.
  factory CustomTheme.fromDaisyJson(Map<String, dynamic> json) {
    final colors = json['colors'];
    if (colors is! Map) {
      throw const FormatException(
        'Not a daisyUI theme: missing "colors" object.',
      );
    }

    Color read(String token) {
      final raw = colors[token];
      if (raw is! String) {
        throw FormatException('Missing or invalid colour token: "$token".');
      }
      return _parseHex(raw, token);
    }

    // Optional token: fall back to another colour when absent.
    Color readOr(String token, Color fallback) {
      final raw = colors[token];
      if (raw is! String) return fallback;
      return _parseHex(raw, token);
    }

    final rawScheme = (json['scheme'] as String?)?.toLowerCase();
    final isDark = rawScheme != 'light';
    final brightness = isDark ? Brightness.dark : Brightness.light;

    // --- daisyUI token -> Dart palette (see designer dartExport mapping) ---
    final primary = read('primary');
    final onPrimary = read('primary-content');
    final secondary = read('secondary');
    final onSecondary = read('secondary-content');
    final tertiary = read('accent');
    final onTertiary = read('accent-content');
    final surface = read('base-100');
    final onSurface = read('base-content');
    final card = read('base-200');
    final outline = read('base-300');
    final error = read('error');
    final onError = read('error-content');
    final success = read('success');
    final warning = read('warning');
    final info = read('info');

    // daisyUI JSON has no dedicated on-success/on-info/on-warning or a distinct
    // "tertiary fixed"; derive sensible defaults so nothing renders unreadable.
    final onSuccess = readOr('success-content', onSurface);
    final onWarning = readOr('warning-content', onSurface);
    final onInfo = readOr('info-content', onSurface);

    final colorScheme = isDark
        ? ColorScheme.dark(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            tertiaryFixed: outline,
            surface: surface,
            onPrimary: onPrimary,
            onSecondary: onSecondary,
            onTertiary: onTertiary,
            onTertiaryFixed: onSurface,
            onSurface: onSurface,
            error: error,
            onError: onError,
            outline: outline,
            shadow: const Color(0xFF000000),
          )
        : ColorScheme.light(
            primary: primary,
            secondary: secondary,
            tertiary: tertiary,
            tertiaryFixed: outline,
            surface: surface,
            onPrimary: onPrimary,
            onSecondary: onSecondary,
            onTertiary: onTertiary,
            onTertiaryFixed: onSurface,
            onSurface: onSurface,
            error: error,
            onError: onError,
            outline: outline,
            shadow: const Color(0xFF000000),
          );

    final themeData = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      cardColor: card,
      scaffoldBackgroundColor: surface,
      extensions: [CornerRadii.xl()],
      textTheme: TextTheme(
        displayLarge: TextStyle(
          color: onSurface,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
        titleLarge: TextStyle(
          color: onSurface,
          fontSize: 24,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: TextStyle(
          color: onSurface,
          fontSize: 18,
          fontWeight: FontWeight.w500,
        ),
        bodyLarge: TextStyle(color: onSurface, fontSize: 16),
        bodyMedium: TextStyle(color: onSurface, fontSize: 14),
        bodySmall: TextStyle(color: onSurface, fontSize: 12),
        labelLarge: TextStyle(
          color: onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );

    final customColors = NeoCustomColors(
      // Battery levels map onto the semantic status colours, matching the
      // designer's Flutter export.
      batteryFull: success,
      batteryMedium: warning,
      batteryLow: error,
      batteryPower: info,
      errorColor: error,
      onErrorColor: onError,
      successColor: success,
      onSuccessColor: onSuccess,
      infoColor: info,
      onInfoColor: onInfo,
      warningColor: warning,
      onWarningColor: onWarning,
    );

    final id = _sanitizeId(json['id'] ?? json['name']);
    final name = (json['name'] as String?)?.trim();

    return CustomTheme(
      id: id,
      name: (name != null && name.isNotEmpty) ? name : id,
      brightness: brightness,
      themeData: themeData,
      customColors: customColors,
      rawJson: Map<String, dynamic>.from(json),
    );
  }

  /// Parses a `#rrggbb` / `#aarrggbb` / `rrggbb` hex string into a [Color].
  static Color _parseHex(String input, String token) {
    var hex = input.trim().replaceAll('#', '').toUpperCase();
    if (hex.length == 6) hex = 'FF$hex';
    if (hex.length != 8) {
      throw FormatException('Colour "$token" is not a hex value: "$input".');
    }
    final value = int.tryParse(hex, radix: 16);
    if (value == null) {
      throw FormatException('Colour "$token" is not a hex value: "$input".');
    }
    return Color(value);
  }

  /// Normalizes a raw id/name into a safe snake-case identifier.
  static String _sanitizeId(Object? raw) {
    final base = (raw is String ? raw : '').toLowerCase();
    final cleaned = base
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return cleaned.isEmpty ? 'custom_theme' : cleaned;
  }
}
