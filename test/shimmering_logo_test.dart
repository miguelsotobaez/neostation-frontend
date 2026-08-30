import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/widgets/shimmering_logo.dart';

/// The sweep repaints a [ShaderMask], which forces an offscreen `saveLayer`.
/// Driven straight off the [AnimationController] that happened once per vsync,
/// so the identical-looking sweep cost four times as much on a 240 Hz display
/// as on a 60 Hz one — during startup and library loading, where the app can
/// least afford it. Repaints are now gated on how far the glint has travelled,
/// which is a clock the animation and the test both share.
void main() {
  Future<void> pumpLogo(WidgetTester tester, {double? progress}) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(child: ShimmeringLogo(width: 200, progress: progress)),
        ),
      ),
    );
  }

  /// The current [ShaderMask] instance. A new one means the sweep repainted.
  ShaderMask maskOf(WidgetTester tester) => tester.widget<ShaderMask>(
    find.descendant(
      of: find.byType(ShimmeringLogo),
      matching: find.byType(ShaderMask),
    ),
  );

  /// Repaints observed while pumping [ticks] frames [interval] apart.
  Future<int> countRepaints(
    WidgetTester tester, {
    required Duration interval,
    required int ticks,
  }) async {
    ShaderMask last = maskOf(tester);
    int repaints = 0;
    for (int i = 0; i < ticks; i++) {
      await tester.pump(interval);
      final ShaderMask now = maskOf(tester);
      if (!identical(now, last)) {
        repaints++;
        last = now;
      }
    }
    return repaints;
  }

  testWidgets('folds several vsyncs into one repaint at 240 Hz', (
    tester,
  ) async {
    await pumpLogo(tester);

    // 60 ticks of 4 ms is 240 ms of a 240 Hz display. Unthrottled that is 60
    // repaints; gating on travel allows 240/2000 of the sweep at 0.0075 a
    // time, so 16.
    final int repaints = await countRepaints(
      tester,
      interval: const Duration(milliseconds: 4),
      ticks: 60,
    );

    expect(repaints, lessThanOrEqualTo(20));
    // Still visibly sweeping, not stalled.
    expect(repaints, greaterThan(5));
  });

  testWidgets('repaints on every tick at 60 Hz', (tester) async {
    await pumpLogo(tester);

    // One 60 Hz frame already travels further than the gate, so nothing is
    // dropped here.
    final int repaints = await countRepaints(
      tester,
      interval: const Duration(milliseconds: 17),
      ticks: 20,
    );

    expect(repaints, greaterThanOrEqualTo(18));
  });

  testWidgets('a progress-driven logo does not run a ticker at rest', (
    tester,
  ) async {
    await pumpLogo(tester, progress: 0.5);
    await tester.pumpAndSettle();

    // With progress supplied the glint tracks the scan instead of sweeping, so
    // there is nothing to animate once it has settled.
    expect(tester.binding.transientCallbackCount, 0);
  });

  testWidgets('the ambient sweep keeps running', (tester) async {
    await pumpLogo(tester);
    await tester.pump(const Duration(milliseconds: 100));

    // No pumpAndSettle here: the ambient sweep is deliberately endless, and
    // settling it would time out.
    expect(tester.binding.transientCallbackCount, greaterThan(0));
  });
}
