import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/widgets/shimmering_logo.dart';
import 'package:neostation/widgets/splash_status_layout.dart';

/// The intro splashes place their status block under a logo that is pinned at
/// the screen centre. The offset used to be a fixed fraction of the screen
/// height, which only cleared the fixed-size logo on a tall enough panel — on
/// short handheld screens the loading text and the scan progress bar were
/// drawn across the glyph. These sizes cover the panels the app ships on, from
/// a 4:3 handheld up to a desktop window.
void main() {
  const sizes = <String, Size>{
    'tiny 4:3 handheld': Size(320, 240),
    // Konkr Pocket Advance: a 3.5" 960x640 3:2 panel (~333ppi). The reported
    // regression came from this device — at xhdpi it is 480x320dp, the
    // shortest panel the app is known to run on, and the old fixed 0.55
    // offset put the status block inside the logo there.
    'Konkr Pocket Advance (xhdpi)': Size(480, 320),
    'Konkr Pocket Advance (hdpi)': Size(640, 427),
    'wide handheld': Size(480, 272),
    // Retroid Nova, 1280x960 at ~356dpi — the geometry sim-nova.sh reproduces.
    'Retroid Nova': Size(575, 431),
    'Thor': Size(831, 467),
    'Steam Deck': Size(1280, 800),
    'desktop': Size(1920, 1080),
  };

  Future<void> pumpAt(
    WidgetTester tester,
    Size size,
    List<Widget> children,
  ) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SplashStatusLayout(children: children)),
      ),
    );
  }

  group('SplashStatusLayout', () {
    for (final entry in sizes.entries) {
      testWidgets('${entry.key}: status clears the logo', (tester) async {
        await pumpAt(tester, entry.value, [
          const SizedBox(
            width: 220,
            child: LinearProgressIndicator(value: 0.4, minHeight: 3),
          ),
          const SizedBox(height: 16),
          const Text('Nintendo 64...', textAlign: TextAlign.center),
        ]);

        final logo = tester.getRect(find.byType(ShimmeringLogo));
        final status = tester.getRect(find.byType(LinearProgressIndicator));
        expect(
          status.top,
          greaterThanOrEqualTo(logo.bottom),
          reason: 'the progress bar must not overlap the logo',
        );
        expect(
          status.bottom,
          lessThanOrEqualTo(entry.value.height),
          reason: 'the status block must stay on screen',
        );
      });

      testWidgets('${entry.key}: two-line status fits below the logo', (
        tester,
      ) async {
        // The startup screen's longest status line: on the narrowest panels it
        // wraps, and the wrapped block still has to fit under the logo.
        await pumpAt(tester, entry.value, [
          const Text(
            'Preparing NeoStation. Waiting for storage and services...',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17),
          ),
        ]);

        final logo = tester.getRect(find.byType(ShimmeringLogo));
        final text = tester.getRect(find.byType(Text));
        expect(text.top, greaterThanOrEqualTo(logo.bottom));
        expect(text.bottom, lessThanOrEqualTo(entry.value.height));
      });
    }

    testWidgets('the logo stays centred on every panel', (tester) async {
      for (final size in sizes.values) {
        await pumpAt(tester, size, const [Text('x')]);
        final logo = tester.getRect(find.byType(ShimmeringLogo));
        expect(logo.center.dx, moreOrLessEquals(size.width / 2, epsilon: 0.5));
        expect(logo.center.dy, moreOrLessEquals(size.height / 2, epsilon: 0.5));
      }
    });

    testWidgets('a tall panel renders the logo at its full width', (
      tester,
    ) async {
      await pumpAt(tester, const Size(831, 467), const [Text('x')]);
      expect(tester.getRect(find.byType(ShimmeringLogo)).width, 280);
    });
  });
}
