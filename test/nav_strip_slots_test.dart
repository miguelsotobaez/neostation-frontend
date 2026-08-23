import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/header_layout.dart';
import 'package:neostation/utils/time_format.dart';

void main() {
  group('navStripMaxSlots', () {
    test('divides what the centred strip has left into slots', () {
      // 1000 wide, a 200 pill mirrored either side with its margin and gutter:
      // 1000 - 2*(200+8+4) = 576, less 2*36 shoulders and 2*4 padding = 496.
      expect(
        navStripMaxSlots(totalWidth: 1000, statusPillWidth: 200),
        496 ~/ 32,
      );
    });

    test('a wider pill costs slots', () {
      final narrow = navStripMaxSlots(totalWidth: 1000, statusPillWidth: 200);
      final wide = navStripMaxSlots(totalWidth: 1000, statusPillWidth: 260);
      expect(wide, lessThan(narrow));
    });

    test('a partial slot does not count', () {
      // Exactly six slots' worth of room, then one pixel less.
      expect(
        navStripMaxSlots(totalWidth: 496, statusPillWidth: 100, minSlots: 1),
        6,
      );
      expect(
        navStripMaxSlots(totalWidth: 495, statusPillWidth: 100, minSlots: 1),
        5,
      );
    });

    test('never goes below the floor, however narrow the screen', () {
      expect(navStripMaxSlots(totalWidth: 600, statusPillWidth: 200), 5);
      expect(navStripMaxSlots(totalWidth: 0, statusPillWidth: 200), 5);
    });

    test('an AYN Thor fits six slots with its battery showing', () {
      // Measured on the device: 832.5 logical wide, a 208.1 status pill with
      // the clock glyph and battery block, and .r scaling the strip by 1.3008.
      expect(
        navStripMaxSlots(
          totalWidth: 832.5,
          statusPillWidth: 208.1,
          slot: 41.63,
          shoulder: 46.83,
          pillPadding: 5.2,
          margin: 10.41,
          gutter: 5.2,
        ),
        6,
      );
    });

    test('dropping the battery block buys several more slots', () {
      // Same screen, a desktop that reports no battery: the block is worth the
      // gap, icon, its gap and the '100%' text.
      final withBattery = navStripMaxSlots(
        totalWidth: 832.5,
        statusPillWidth: 208.1,
        slot: 41.63,
        shoulder: 46.83,
        pillPadding: 5.2,
        margin: 10.41,
        gutter: 5.2,
      );
      final withoutBattery = navStripMaxSlots(
        totalWidth: 832.5,
        statusPillWidth: 208.1 - 67.6,
        slot: 41.63,
        shoulder: 46.83,
        pillPadding: 5.2,
        margin: 10.41,
        gutter: 5.2,
      );
      expect(withoutBattery, greaterThanOrEqualTo(7));
      expect(withoutBattery, greaterThan(withBattery));
    });
  });

  group('widestClockText', () {
    test('covers every time the formatter can produce', () {
      for (final use12Hour in [false, true]) {
        final widest = widestClockText(use12Hour: use12Hour).length;
        for (var hour = 0; hour < 24; hour++) {
          for (final minute in [0, 9, 59]) {
            final text = formatClockTime(
              DateTime(2026, 1, 1, hour, minute),
              use12Hour: use12Hour,
            );
            expect(
              text.length,
              lessThanOrEqualTo(widest),
              reason: '$text is wider than the reserved worst case',
            );
          }
        }
      }
    });

    test('reserves room for the AM/PM suffix only in 12-hour form', () {
      expect(widestClockText(use12Hour: true), contains('PM'));
      expect(widestClockText(use12Hour: false), '23:59');
    });
  });
}
