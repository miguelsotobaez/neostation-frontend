/// Pure directional navigation for row-major selection grids.
///
/// Extracted from the games grid so the wrap-around rules live in one
/// testable place and can be reused by any grid with the same semantics:
///
/// * Up/Down move a full row, wrapping to the opposite edge while preserving
///   the column (clamping into the last row's actual length).
/// * Left/Right move one cell, wrapping to the row's ends (clamping into the
///   last row's actual length when wrapping right).
library;

/// Moves [index] one row up, wrapping to the last row on overflow.
int gridMoveUp({
  required int index,
  required int columns,
  required int itemCount,
}) {
  if (itemCount <= 0) return 0;
  final c = columns.clamp(1, itemCount);
  int ni = index - c;
  if (ni < 0) {
    final col = index % c;
    ni = ((itemCount / c).ceil() - 1) * c + col;
    while (ni >= itemCount) {
      ni -= c;
    }
    if (ni < 0) ni = index;
  }
  return ni.clamp(0, itemCount - 1);
}

/// Moves [index] one row down, wrapping to the first row on overflow.
int gridMoveDown({
  required int index,
  required int columns,
  required int itemCount,
}) {
  if (itemCount <= 0) return 0;
  final c = columns.clamp(1, itemCount);
  int ni = index + c;
  if (ni >= itemCount) {
    ni = index % c;
  }
  return ni.clamp(0, itemCount - 1);
}

/// Moves [index] one cell left, wrapping to the row's right edge on overflow.
int gridMoveLeft({
  required int index,
  required int columns,
  required int itemCount,
}) {
  if (itemCount <= 0) return 0;
  final c = columns.clamp(1, itemCount);
  final int ni;
  if (index % c == 0) {
    final wrapRight = (index ~/ c) * c + c - 1;
    ni = wrapRight < itemCount - 1 ? wrapRight : itemCount - 1;
  } else {
    ni = index - 1;
  }
  return ni.clamp(0, itemCount - 1);
}

/// Moves [index] one cell right, wrapping to the row's left edge on overflow.
int gridMoveRight({
  required int index,
  required int columns,
  required int itemCount,
}) {
  if (itemCount <= 0) return 0;
  final c = columns.clamp(1, itemCount);
  final next = index + 1;
  final ni = (next % c == 0 || next >= itemCount) ? (index ~/ c) * c : next;
  return ni.clamp(0, itemCount - 1);
}
