import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/secondary_display_state.dart';
import 'package:neostation/screens/secondary_screen/background_builders.dart';
import 'package:neostation/themes/app_themes.dart';

/// Pumps [child] under a MaterialApp themed with [theme] and reports the
/// colour the resulting Container paints.
Future<Color?> _paintedColor(
  WidgetTester tester,
  ThemeData theme,
  Widget child,
) async {
  await tester.pumpWidget(MaterialApp(theme: theme, home: child));
  final container = tester.widget<Container>(find.byType(Container));
  final decoration = container.decoration;
  if (decoration is BoxDecoration) return decoration.color;
  return container.color;
}

void main() {
  group('buildShaderFallback', () {
    // The state the secondary display holds during startup: the main engine
    // has pushed nothing yet, so there is no background colour to use.
    final welcome = SecondaryDisplayStateData(systemName: 'WELCOME');

    testWidgets('uses the theme background when none has been pushed', (
      tester,
    ) async {
      // The regression: this used to be a hardcoded Colors.black, which left
      // a light-theme user staring at a dark panel for the whole boot.
      final color = await _paintedColor(
        tester,
        AppThemes.lightTheme,
        buildShaderFallback(welcome),
      );

      expect(color, AppThemes.lightTheme.scaffoldBackgroundColor);
      expect(color, isNot(Colors.black));
    });

    testWidgets('still resolves to black under the OLED theme', (tester) async {
      // buildSystemBackground documents that the empty case preserves the OLED
      // look; OLED's scaffold colour is pure black, so that holds without a
      // special case here.
      final color = await _paintedColor(
        tester,
        AppThemes.oledTheme,
        buildShaderFallback(welcome),
      );

      expect(color, const Color(0xFF000000));
    });

    testWidgets('a pushed background colour still wins over the theme', (
      tester,
    ) async {
      const pushed = 0xFF123456;
      final withBackground = SecondaryDisplayStateData(
        systemName: 'snes',
        backgroundColor: pushed,
      );

      final color = await _paintedColor(
        tester,
        AppThemes.lightTheme,
        buildShaderFallback(withBackground),
      );

      expect(color, const Color(pushed));
    });
  });
}
