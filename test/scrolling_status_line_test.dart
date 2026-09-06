import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/screens/game_screen/game_details_card/widgets/scrolling_status_line.dart';

/// The details card footer's marquee. Its whole contract is invisible to a
/// screenshot taken at the wrong moment — it only moves when the row overflows,
/// and it ping-pongs rather than snapping back — so it is pinned down here.
void main() {
  Future<void> pumpStrip(
    WidgetTester tester, {
    required double slotWidth,
    required double contentWidth,
    String resetKey = 'a',
    double shadowRoom = 0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: slotWidth,
              height: 20,
              child: ScrollingStatusLine(
                resetKey: resetKey,
                shadowRoom: shadowRoom,
                children: [SizedBox(width: contentWidth, height: 20)],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double offsetOf(WidgetTester tester) =>
      tester.widget<Scrollable>(find.byType(Scrollable)).controller!.offset;

  /// Runs the marquee's periodic timer for [ticks] frames, returning every
  /// offset it passed through. One long `pump` would elapse the clock but let
  /// the timer run only once, so the movement has to be driven frame by frame.
  Future<List<double>> track(WidgetTester tester, int ticks) async {
    final List<double> offsets = [];
    for (int i = 0; i < ticks; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      offsets.add(offsetOf(tester));
    }
    return offsets;
  }

  testWidgets('sits still when the row fits its slot', (tester) async {
    await pumpStrip(tester, slotWidth: 200, contentWidth: 120);

    final List<double> offsets = await track(tester, 100);
    expect(offsets.every((o) => o == 0), isTrue);
  });

  testWidgets('scrolls out to the end of an overflowing row, then back', (
    tester,
  ) async {
    // 400 of content in a 100 slot: 300 to travel.
    await pumpStrip(tester, slotWidth: 100, contentWidth: 400);

    // Held still at first, so the start of the row is readable before it moves.
    final List<double> hold = await track(tester, 10);
    expect(hold.every((o) => o == 0), isTrue);

    final List<double> offsets = await track(tester, 600);
    final double peak = offsets.reduce((a, b) => a > b ? a : b);

    // Reaches the far end exactly, and does not scroll on into empty space.
    expect(peak, 300);

    // Comes back rather than snapping to the start: after the peak it is seen
    // at intermediate offsets on the way down, not just at zero.
    final int peakAt = offsets.indexOf(peak);
    final List<double> after = offsets.sublist(peakAt);
    expect(after.any((o) => o > 0 && o < peak), isTrue);

    // ...and all the way back to the start, before setting off again.
    expect(after.any((o) => o == 0), isTrue);

    // Let the last scheduled hold expire so no timer outlives the test.
    await track(tester, 60);
  });

  testWidgets('restarts from the left when the selection changes', (
    tester,
  ) async {
    await pumpStrip(tester, slotWidth: 100, contentWidth: 400);
    await track(tester, 60);
    expect(offsetOf(tester), greaterThan(0));

    await pumpStrip(
      tester,
      slotWidth: 100,
      contentWidth: 400,
      resetKey: 'another-game',
    );
    await tester.pump();
    expect(offsetOf(tester), 0);

    // Clean up the timer the new strip scheduled.
    await track(tester, 60);
  });

  /// The clip, which is a separate contract from the movement above and the
  /// one a screenshot can see least of all.
  ///
  /// `SingleChildScrollView` clips only once its content overflows, and then to
  /// its viewport rect in *both* axes. The details footer's lines are fixed at
  /// 15.r and 16.r with about a pixel of slack, so a shadowed line that fits
  /// keeps its whole shadow and the same line scrolling loses the bottom of it
  /// — the shadow changes at the instant the marquee starts. `shadowRoom` is
  /// what makes both states paint the same.
  group('shadowRoom', () {
    /// The strip's own slack clip, picked out by its clipper: the viewport
    /// inside it renders a plain `ClipRect` of its own, so type alone would
    /// match either one.
    CustomClipper<Rect>? slackClipper(WidgetTester tester) {
      final Iterable<ClipRect> ours = tester
          .widgetList<ClipRect>(
            find.descendant(
              of: find.byType(ScrollingStatusLine),
              matching: find.byType(ClipRect),
            ),
          )
          .where((clip) => clip.clipper != null);
      return ours.isEmpty ? null : ours.single.clipper;
    }

    Clip viewportClip(WidgetTester tester) => tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .clipBehavior;

    testWidgets('clips to its own box when no room is asked for', (
      tester,
    ) async {
      await pumpStrip(tester, slotWidth: 100, contentWidth: 400);

      expect(viewportClip(tester), Clip.hardEdge);
      expect(slackClipper(tester), isNull);

      await track(tester, 60);
    });

    testWidgets('hands the clip over and opens it vertically when it is', (
      tester,
    ) async {
      await pumpStrip(tester, slotWidth: 100, contentWidth: 400, shadowRoom: 6);

      // The viewport must stop clipping, or its box is still what cuts the
      // shadow off no matter what is wrapped around it.
      expect(viewportClip(tester), Clip.none);

      final CustomClipper<Rect> clipper = slackClipper(tester)!;

      // Horizontal edges exactly on the line's width — that clip is the one
      // hiding the off-screen end of the strip and has to stay put. Vertical
      // edges opened by the room asked for.
      expect(
        clipper.getClip(const Size(100, 20)),
        const Rect.fromLTRB(0, -6, 100, 26),
      );

      await track(tester, 60);
    });

    testWidgets('still scrolls with the clip handed over', (tester) async {
      // The slack clip sits between the strip and its viewport, so it is worth
      // one check that it did not break the movement the tests above pin.
      await pumpStrip(tester, slotWidth: 100, contentWidth: 400, shadowRoom: 6);

      final List<double> offsets = await track(tester, 200);
      expect(offsets.any((o) => o > 0), isTrue);

      await track(tester, 60);
    });
  });
}
