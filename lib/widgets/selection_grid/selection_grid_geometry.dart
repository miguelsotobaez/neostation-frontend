/// Pure spatial-layout math for [SelectionGrid].
///
/// These helpers are extracted so the grid geometry can be unit-tested in
/// isolation and reused by any grid that needs a selection highlight aligned
/// with its cards by construction (the highlight and the cards consume the
/// exact same rectangles).
library;

/// A single card's rectangle in grid-content coordinates
/// (origin = the top-left of the first grid cell, padding excluded).
class GridCellRect {
  final double left;
  final double top;
  final double width;
  final double height;

  const GridCellRect({
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  double get right => left + width;
  double get bottom => top + height;
}

/// A horizontal band of cards sharing the same vertical extent.
class GridRowInfo {
  /// Content-space Y of the row's top edge.
  final double top;

  /// Height of the tallest card in the row.
  final double height;
  final int startIndex;
  final int count;

  const GridRowInfo({
    required this.top,
    required this.height,
    required this.startIndex,
    required this.count,
  });

  double get bottom => top + height;
}

/// Complete, immutable layout snapshot consumed by [SelectionGrid].
///
/// Both the cards and the selection highlight are positioned from
/// [cardRects], so they can never drift apart.
class SelectionGridGeometry {
  final int itemCount;
  final int columns;

  /// Width of the grid content area (already net of any outer padding).
  final double contentWidth;
  final double cardWidth;
  final double spacingX;
  final double spacingY;

  /// Total scrollable content height, including per-row trailing spacing.
  final double totalHeight;
  final List<GridCellRect> cardRects;
  final List<GridRowInfo> rows;

  const SelectionGridGeometry({
    required this.itemCount,
    required this.columns,
    required this.contentWidth,
    required this.cardWidth,
    required this.spacingX,
    required this.spacingY,
    required this.totalHeight,
    required this.cardRects,
    required this.rows,
  });

  /// Rectangle for [index], clamped into range for safety.
  GridCellRect rectFor(int index) {
    if (cardRects.isEmpty) {
      return const GridCellRect(left: 0, top: 0, width: 0, height: 0);
    }
    return cardRects[index.clamp(0, cardRects.length - 1)];
  }
}

/// Computes a row-major grid layout where each card's height is provided by
/// [itemHeightFor] (use a constant closure for uniform-height grids).
///
/// Cards in the same row share the row's max height band; shorter cards are
/// vertically centered inside the band (including the row's trailing spacing),
/// matching the visual centering the games grid has always used.
SelectionGridGeometry computeSelectionGridGeometry({
  required int itemCount,
  required int columns,
  required double availableWidth,
  required double spacingX,
  required double spacingY,
  required double Function(int index, double cardWidth) itemHeightFor,
}) {
  final cols = columns.clamp(1, 100);
  final cardWidth = cols > 0
      ? (availableWidth - (cols - 1) * spacingX) / cols
      : availableWidth;

  final rects = List<GridCellRect?>.filled(itemCount, null);
  final rows = <GridRowInfo>[];

  double y = 0;
  int i = 0;
  while (i < itemCount) {
    final end = (i + cols).clamp(0, itemCount);

    // Resolve each card's height once, then derive the row's band height.
    final heights = List<double>.generate(
      end - i,
      (j) => itemHeightFor(i + j, cardWidth),
    );
    double maxH = 0;
    for (final h in heights) {
      if (h > maxH) maxH = h;
    }

    rows.add(GridRowInfo(top: y, height: maxH, startIndex: i, count: end - i));

    for (int idx = i; idx < end; idx++) {
      final col = idx % cols;
      final h = heights[idx - i];
      rects[idx] = GridCellRect(
        left: col * (cardWidth + spacingX),
        top: y + (maxH + spacingY - h) / 2,
        width: cardWidth,
        height: h,
      );
    }

    y += maxH + spacingY;
    i = end;
  }

  return SelectionGridGeometry(
    itemCount: itemCount,
    columns: cols,
    contentWidth: availableWidth,
    cardWidth: cardWidth,
    spacingX: spacingX,
    spacingY: spacingY,
    totalHeight: y,
    cardRects: List<GridCellRect>.unmodifiable(rects.cast<GridCellRect>()),
    rows: List<GridRowInfo>.unmodifiable(rows),
  );
}
