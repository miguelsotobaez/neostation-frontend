/// Directional selection helpers for gamepad/d-pad list navigation.
///
/// Used where some
/// rows may be disabled (skipped) and the ends clamp instead of wrapping.
///
/// Both functions are bounded by [total], so a fully-disabled list can never
/// spin forever — the previous clamp-in-a-`do/while` implementation could loop
/// indefinitely when the clamped index landed on a disabled row (see #217).
library;

/// Returns the nearest enabled index strictly above [current], or [current]
/// itself when there is no enabled row above it (clamps at the top, no wrap).
int previousEnabledIndex(int current, int total, bool Function(int) isEnabled) {
  for (int idx = current - 1; idx >= 0; idx--) {
    if (isEnabled(idx)) return idx;
  }
  return current;
}

/// Returns the nearest enabled index strictly below [current], or [current]
/// itself when there is no enabled row below it (clamps at the bottom, no wrap).
int nextEnabledIndex(int current, int total, bool Function(int) isEnabled) {
  for (int idx = current + 1; idx < total; idx++) {
    if (isEnabled(idx)) return idx;
  }
  return current;
}
