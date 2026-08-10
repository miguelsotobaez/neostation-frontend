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

    test('keeps the window still while the selection stays inside it', () {
      for (var slot = 1; slot <= 6; slot++) {
        expect(
          navTabWindowStart(
            windowStart: 1,
            selectedSlot: slot,
            tabCount: 8,
            maxSlots: 6,
          ),
          1,
        );
      }
    });

    test(
      'shifts right just far enough when the selection walks off the end',
      () {
        expect(
          navTabWindowStart(
            windowStart: 0,
            selectedSlot: 6,
            tabCount: 8,
            maxSlots: 6,
          ),
          1,
        );
      },
    );

    test('shifts left to the selection when it walks off the start', () {
      expect(
        navTabWindowStart(
          windowStart: 2,
          selectedSlot: 1,
          tabCount: 8,
          maxSlots: 6,
        ),
        1,
      );
    });

    test('wrap-around jumps the window to the far end', () {
      // R1 from the last tab wraps to slot 0.
      expect(
        navTabWindowStart(
          windowStart: 2,
          selectedSlot: 0,
          tabCount: 8,
          maxSlots: 6,
        ),
        0,
      );
      // L1 from the first tab wraps to the last slot.
      expect(
        navTabWindowStart(
          windowStart: 0,
          selectedSlot: 7,
          tabCount: 8,
          maxSlots: 6,
        ),
        2,
      );
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
