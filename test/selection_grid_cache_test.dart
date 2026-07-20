import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/widgets/selection_grid/selection_grid.dart';
import 'package:neostation/widgets/selection_grid/selection_grid_geometry.dart';

/// Guards the per-index cell cache that makes grid navigation cheap: cards must
/// be reused (not rebuilt) when the visible window shifts, and must be rebuilt
/// when the parent bumps [SelectionGrid.revision]. Regressing the first
/// reintroduces the #188 "rebuild the whole visible window every frame" jank;
/// regressing the second freezes live card content (e.g. scrape progress).
void main() {
  // 4-column grid, 100 uniform 100px-tall cells, no spacing → 25 rows of 100px.
  SelectionGridGeometry buildGeometry() => computeSelectionGridGeometry(
    itemCount: 100,
    columns: 4,
    availableWidth: 400,
    spacingX: 0,
    spacingY: 0,
    itemHeightFor: (_, _) => 100,
  );

  /// Pumps a SelectionGrid whose itemBuilder tallies how many times each index
  /// is built. Returns the (live) tally map and a setter that re-pumps with new
  /// selection/revision values.
  Future<(Map<int, int>, Future<void> Function({int? sel, int? rev}))> pumpGrid(
    WidgetTester tester,
  ) async {
    final buildCounts = <int, int>{};
    final geometry = buildGeometry();

    late StateSetter setOuter;
    var selectedIndex = 0;
    var revision = 0;

    await tester.pumpWidget(
      ScreenUtilInit(
        designSize: const Size(400, 300),
        builder: (context, _) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 300, // ~3 rows visible
                child: StatefulBuilder(
                  builder: (context, setState) {
                    setOuter = setState;
                    return SelectionGrid(
                      geometry: geometry,
                      padding: EdgeInsets.zero,
                      selectedIndex: selectedIndex,
                      revision: revision,
                      highlightBuilder: (_) => const SizedBox.shrink(),
                      itemBuilder: (context, index, size) {
                        buildCounts[index] = (buildCounts[index] ?? 0) + 1;
                        return const SizedBox.expand();
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Future<void> apply({int? sel, int? rev}) async {
      setOuter(() {
        if (sel != null) selectedIndex = sel;
        if (rev != null) revision = rev;
      });
      await tester.pump();
    }

    return (buildCounts, apply);
  }

  testWidgets('scroll shift reuses already-built cells, builds only new rows', (
    tester,
  ) async {
    final (buildCounts, _) = await pumpGrid(tester);
    final initialBuilt = buildCounts.keys.toSet();
    expect(initialBuilt, isNotEmpty, reason: 'sanity: some cells built');

    // Scroll down far enough that the visible window shifts and deeper rows
    // enter (well past the buffer).
    await tester.drag(find.byType(Scrollable), const Offset(0, -600));
    await tester.pumpAndSettle();

    // The window really did move — rows that were off-screen are now built.
    final newlyBuilt = buildCounts.keys.where((i) => !initialBuilt.contains(i));
    expect(
      newlyBuilt,
      isNotEmpty,
      reason: 'window shifted, so new rows were built',
    );

    // The core invariant: across pure scrolling (no revision/geometry change)
    // no cell is ever built more than once — every still/again-visible index is
    // served from the per-index cache instead of being rebuilt.
    final rebuiltTwice = buildCounts.entries
        .where((e) => e.value > 1)
        .map((e) => e.key)
        .toList();
    expect(
      rebuiltTwice,
      isEmpty,
      reason:
          'no cell rebuilt across scrolling — all reused by the index cache',
    );
  });

  testWidgets('bumping revision rebuilds visible cells', (tester) async {
    final (buildCounts, setProps) = await pumpGrid(tester);

    expect(buildCounts[0], 1);

    await setProps(rev: 1);

    expect(
      buildCounts[0],
      2,
      reason: 'revision bump invalidates the cache and rebuilds visible cells',
    );
  });

  testWidgets('re-pump with unchanged inputs does not rebuild cells', (
    tester,
  ) async {
    final (buildCounts, setProps) = await pumpGrid(tester);

    expect(buildCounts[0], 1);

    // Same selection, same revision → cache hit, no itemBuilder calls.
    await setProps();

    expect(
      buildCounts[0],
      1,
      reason: 'unchanged inputs reuse cached cells (no rebuild churn)',
    );
  });
}
