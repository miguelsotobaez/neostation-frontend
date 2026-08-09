import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/bounded_concurrency.dart';

void main() {
  group('runBounded', () {
    test('processes every item exactly once', () async {
      final items = List.generate(50, (i) => i);
      final seen = <int>[];

      await runBounded<int>(items, 6, (item) async {
        seen.add(item);
      });

      expect(seen.length, items.length);
      expect(seen.toSet(), items.toSet());
    });

    test('never exceeds the concurrency limit', () async {
      var inFlight = 0;
      var peak = 0;

      await runBounded<int>(List.generate(40, (i) => i), 6, (_) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
      });

      expect(peak, lessThanOrEqualTo(6));
      // Sanity check that work really did overlap, so the bound above is
      // meaningful rather than trivially satisfied by serial execution.
      expect(peak, greaterThan(1));
    });

    test('uses fewer workers than the limit when items are scarce', () async {
      var peak = 0;
      var inFlight = 0;

      await runBounded<int>([1, 2], 8, (_) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        inFlight--;
      });

      expect(peak, lessThanOrEqualTo(2));
    });

    test('a failing task does not abort the batch', () async {
      final completed = <int>[];

      await runBounded<int>(List.generate(10, (i) => i), 3, (item) async {
        if (item.isEven) throw StateError('boom $item');
        completed.add(item);
      });

      expect(completed.toSet(), {1, 3, 5, 7, 9});
    });

    test('reports progress once per item, including failures', () async {
      var progress = 0;

      await runBounded<int>(List.generate(10, (i) => i), 4, (item) async {
        if (item.isEven) throw StateError('boom $item');
      }, onEach: () => progress++);

      expect(progress, 10);
    });

    test('returns immediately for an empty item list', () async {
      var called = false;

      await runBounded<int>([], 4, (_) async => called = true);

      expect(called, isFalse);
    });
  });
}
