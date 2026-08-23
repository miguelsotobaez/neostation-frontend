import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/nav_tabs.dart';

void main() {
  group('navTabWindowStart', () {
    test('never scrolls when tabs fit in the window', () {
      for (var count = 1; count <= 6; count++) {
        expect(
          navTabWindowStart(
            windowStart: 3,
            selectedSlot: count - 1,
            tabCount: count,
            maxSlots: 6,
          ),
          0,
          reason: '$count tabs fit in 6 slots',
        );
      }
    });

    test('keeps the selection in the middle slot mid-strip', () {
      // 6 tabs through a 3-slot window: slots 2 and 3 are far enough from
      // both ends to center exactly.
      expect(
        navTabWindowStart(
          windowStart: 0,
          selectedSlot: 2,
          tabCount: 6,
          maxSlots: 3,
        ),
        1,
      );
      expect(
        navTabWindowStart(
          windowStart: 1,
          selectedSlot: 3,
          tabCount: 6,
          maxSlots: 3,
        ),
        2,
      );
    });

    test('sits left of middle for an even window width', () {
      // 8 tabs through a 6-slot window: slot 3 renders in window slot 2.
      expect(
        navTabWindowStart(
          windowStart: 0,
          selectedSlot: 3,
          tabCount: 8,
          maxSlots: 6,
        ),
        1,
      );
    });

    test('clamps at the far left instead of showing blank slots', () {
      for (final slot in [0, 1]) {
        expect(
          navTabWindowStart(
            windowStart: 2,
            selectedSlot: slot,
            tabCount: 6,
            maxSlots: 3,
          ),
          0,
          reason: 'slot $slot is within half a window of the start',
        );
      }
    });

    test('clamps at the far right instead of showing blank slots', () {
      for (final slot in [4, 5]) {
        expect(
          navTabWindowStart(
            windowStart: 0,
            selectedSlot: slot,
            tabCount: 6,
            maxSlots: 3,
          ),
          3,
          reason: 'slot $slot is within half a window of the end',
        );
      }
    });

    test('keeps the current window when the selected tab is hidden', () {
      expect(
        navTabWindowStart(
          windowStart: 1,
          selectedSlot: -1,
          tabCount: 8,
          maxSlots: 6,
        ),
        1,
      );
    });

    test('clamps a stale window after tabs are hidden', () {
      // Window sat at the end of a 9-tab strip; two tabs got hidden.
      expect(
        navTabWindowStart(
          windowStart: 3,
          selectedSlot: -1,
          tabCount: 7,
          maxSlots: 6,
        ),
        1,
      );
    });
  });
}
