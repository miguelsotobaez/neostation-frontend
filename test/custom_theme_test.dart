import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/themes/custom_theme.dart';

// A minimal but complete daisyUI theme JSON, matching the shape exported by the
// NeoStation theme designer (hex values, daisyUI-named tokens).
const _daisyJson = {
  'name': 'My Custom Theme',
  'id': 'my_custom_theme',
  'scheme': 'dark',
  'colors': {
    'base-100': '#282a36',
    'base-200': '#1f202a',
    'base-300': '#303241',
    'base-content': '#f8f8f3',
    'primary': '#ff79c6',
    'primary-content': '#16050e',
    'secondary': '#bd93f9',
    'secondary-content': '#0d0815',
    'accent': '#ffb86c',
    'accent-content': '#160d04',
    'neutral': '#414558',
    'info': '#8be9fd',
    'info-content': '#071316',
    'success': '#51fa7b',
    'success-content': '#021505',
    'warning': '#f1fa8c',
    'warning-content': '#141507',
    'error': '#ff5555',
    'error-content': '#160202',
  },
  'effects': {'radius-box': '1rem', 'border': '1px'},
};

void main() {
  group('CustomTheme.fromDaisyJson', () {
    test('maps daisyUI tokens onto the Dart palette (designer mapping)', () {
      final theme = CustomTheme.fromDaisyJson(_daisyJson);

      expect(theme.id, 'my_custom_theme');
      expect(theme.name, 'My Custom Theme');
      expect(theme.brightness, Brightness.dark);

      final scheme = theme.themeData.colorScheme;
      expect(scheme.primary, const Color(0xFFFF79C6));
      expect(scheme.onPrimary, const Color(0xFF16050E));
      expect(scheme.secondary, const Color(0xFFBD93F9));
      expect(scheme.tertiary, const Color(0xFFFFB86C)); // accent -> tertiary
      expect(scheme.surface, const Color(0xFF282A36)); // base-100
      expect(scheme.onSurface, const Color(0xFFF8F8F3)); // base-content
      expect(scheme.outline, const Color(0xFF303241)); // base-300
      expect(scheme.error, const Color(0xFFFF5555));
      expect(theme.themeData.cardColor, const Color(0xFF1F202A)); // base-200
      expect(theme.themeData.scaffoldBackgroundColor, scheme.surface);
    });

    test('battery + status custom colours follow the designer mapping', () {
      final theme = CustomTheme.fromDaisyJson(_daisyJson);
      final c = theme.customColors;

      expect(c.batteryFull, const Color(0xFF51FA7B)); // success
      expect(c.batteryMedium, const Color(0xFFF1FA8C)); // warning
      expect(c.batteryLow, const Color(0xFFFF5555)); // error
      expect(c.successColor, const Color(0xFF51FA7B));
      expect(c.onSuccessColor, const Color(0xFF021505));
      expect(c.infoColor, const Color(0xFF8BE9FD));
    });

    test('light scheme produces a light ColorScheme', () {
      final json = Map<String, dynamic>.from(_daisyJson)..['scheme'] = 'light';
      final theme = CustomTheme.fromDaisyJson(json);
      expect(theme.brightness, Brightness.light);
      expect(theme.themeData.colorScheme.brightness, Brightness.light);
    });

    test('missing on-* tokens fall back to base-content', () {
      final colors = Map<String, dynamic>.from(
        _daisyJson['colors'] as Map,
      )..remove('success-content');
      final json = Map<String, dynamic>.from(_daisyJson)..['colors'] = colors;
      final theme = CustomTheme.fromDaisyJson(json);
      expect(theme.customColors.onSuccessColor, const Color(0xFFF8F8F3));
    });

    test('sanitizes id and derives one from name when absent', () {
      final json = Map<String, dynamic>.from(_daisyJson)
        ..remove('id')
        ..['name'] = 'Neon Sunset!!';
      final theme = CustomTheme.fromDaisyJson(json);
      expect(theme.id, 'neon_sunset');
    });

    test('accepts 6- and 8-digit hex', () {
      final colors = Map<String, dynamic>.from(_daisyJson['colors'] as Map)
        ..['primary'] = 'FF79C6' // no leading '#'
        ..['secondary'] = '#BD93F9FF'; // 8-digit RRGGBBAA-style value
      final json = Map<String, dynamic>.from(_daisyJson)..['colors'] = colors;
      final theme = CustomTheme.fromDaisyJson(json);
      expect(theme.themeData.colorScheme.primary, const Color(0xFFFF79C6));
      expect(theme.themeData.colorScheme.secondary, const Color(0xBD93F9FF));
    });

    test('throws FormatException on missing colors', () {
      expect(
        () => CustomTheme.fromDaisyJson({'name': 'x'}),
        throwsFormatException,
      );
    });

    test('throws FormatException on a missing required token', () {
      final colors = Map<String, dynamic>.from(
        _daisyJson['colors'] as Map,
      )..remove('primary');
      final json = Map<String, dynamic>.from(_daisyJson)..['colors'] = colors;
      expect(() => CustomTheme.fromDaisyJson(json), throwsFormatException);
    });

    test('throws FormatException on a non-hex value', () {
      final colors = Map<String, dynamic>.from(_daisyJson['colors'] as Map)
        ..['primary'] = 'oklch(75% 0.1 200)';
      final json = Map<String, dynamic>.from(_daisyJson)..['colors'] = colors;
      expect(() => CustomTheme.fromDaisyJson(json), throwsFormatException);
    });
  });
}
