import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neostation/widgets/native_carousel.dart';

/// Stepping past either end of the games carousel continues from the other.
///
/// It is opt-in per carousel: the systems carousel is a short row the user
/// reads as a row, where running off the end is information. The games
/// carousel has thousands of pages and no readable end, so a dead press at the
/// last card reads as dropped input.
void main() {
  Future<GlobalKey<NativeCarouselState>> pumpCarousel(
    WidgetTester tester, {
    required int itemCount,
    required int initialIndex,
    required bool wrap,
  }) async {
    final key = GlobalKey<NativeCarouselState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 400,
            child: NativeCarousel(
              key: key,
              itemCount: itemCount,
              initialIndex: initialIndex,
              wrap: wrap,
              itemBuilder: (context, index) => Center(child: Text('$index')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return key;
  }

  testWidgets('the last card steps forward to the first', (tester) async {
    final key = await pumpCarousel(
      tester,
      itemCount: 5,
      initialIndex: 4,
      wrap: true,
    );

    key.currentState!.nextPage();
    await tester.pumpAndSettle();

    expect(key.currentState!.currentIndex, 0);
  });

  testWidgets('the first card steps back to the last', (tester) async {
    final key = await pumpCarousel(
      tester,
      itemCount: 5,
      initialIndex: 0,
      wrap: true,
    );

    key.currentState!.previousPage();
    await tester.pumpAndSettle();

    expect(key.currentState!.currentIndex, 4);
  });

  testWidgets('without wrap the ends still stop', (tester) async {
    final key = await pumpCarousel(
      tester,
      itemCount: 5,
      initialIndex: 4,
      wrap: false,
    );

    key.currentState!.nextPage();
    await tester.pumpAndSettle();

    expect(
      key.currentState!.currentIndex,
      4,
      reason: 'the systems carousel opts out and must be unaffected',
    );
  });

  testWidgets('a single-page carousel does not wrap onto itself', (
    tester,
  ) async {
    final key = await pumpCarousel(
      tester,
      itemCount: 1,
      initialIndex: 0,
      wrap: true,
    );

    key.currentState!.nextPage();
    key.currentState!.previousPage();
    await tester.pumpAndSettle();

    expect(key.currentState!.currentIndex, 0);
  });
}
