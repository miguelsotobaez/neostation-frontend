import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The header's tab strip renders inside a pill whose `Border` deflates the
/// space its child gets. The scrolling strip must live within that deflated
/// box like the static one does: a positioned child with a stated height
/// ignores the border and renders the icons off a taller axis, which showed up
/// as every icon jumping ~14% larger the moment a hidden tab pushed the strip
/// past [minNavTabSlots].
///
/// Mirrors `_buildScrollingStrip` / the static branch in `lib/widgets/header.dart`.
void main() {
  const slot = 32.0;
  const pad = 8.0;
  const border = 1.0;

  final boxes = <BoxConstraints>[];

  Widget tabButton() => Container(
    padding: const EdgeInsets.all(pad),
    child: LayoutBuilder(
      builder: (context, constraints) {
        boxes.add(constraints);
        return const SizedBox.expand();
      },
    ),
  );

  Widget strip(int tabCount) => Stack(
    children: [
      Positioned(left: 0, top: 4, bottom: 4, width: slot, child: Container()),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < tabCount; i++)
            SizedBox(width: slot, height: slot, child: tabButton()),
        ],
      ),
    ],
  );

  /// The pill: fixed height, and a border that eats into the child's box.
  Widget pill(Widget child) => Container(
    height: slot,
    decoration: BoxDecoration(border: Border.all(width: border)),
    child: child,
  );

  Widget scrolling(int tabCount) => SizedBox(
    width: 5 * slot,
    height: slot,
    child: ClipRect(
      child: Stack(
        children: [
          Positioned(
            left: -slot,
            top: 0,
            bottom: 0,
            width: tabCount * slot,
            child: strip(tabCount),
          ),
        ],
      ),
    ),
  );

  Future<BoxConstraints> iconBox(WidgetTester tester, Widget child) async {
    boxes.clear();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(child: pill(child)),
      ),
    );
    return boxes.first;
  }

  testWidgets('scrolled and static strips give icons the same box', (
    tester,
  ) async {
    final staticBox = await iconBox(tester, strip(5));
    final scrolledBox = await iconBox(tester, scrolling(6));

    expect(scrolledBox, staticBox);
    // And the box is the one the border leaves behind, not the nominal slot.
    expect(staticBox.maxHeight, slot - (2 * pad) - (2 * border));
  });
}
