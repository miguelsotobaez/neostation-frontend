import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

/// The compact "Label: value" control used by searchable filter screens.
class SearchFilterChip extends StatelessWidget {
  const SearchFilterChip({
    super.key,
    required this.label,
    required this.value,
    required this.isFocused,
    required this.isActive,
    required this.onTap,
    this.maxValueWidth,
  });

  final String label;
  final String value;
  final bool isFocused;
  final bool isActive;
  final VoidCallback onTap;
  final double? maxValueWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.only(right: 8.r),
        padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 8.r),
        decoration: BoxDecoration(
          color: isFocused
              ? scheme.primary.withValues(alpha: 0.18)
              : isActive
              ? scheme.primary.withValues(alpha: 0.10)
              : scheme.surface.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(
            color: isFocused
                ? scheme.primary
                : isActive
                ? scheme.primary.withValues(alpha: 0.5)
                : Colors.transparent,
            width: 2.r,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$label: ',
              style: TextStyle(
                fontSize: 13.r,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxValueWidth ?? 140.r),
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.r,
                  fontWeight: FontWeight.w700,
                  color: isActive || isFocused
                      ? scheme.primary
                      : scheme.onSurface,
                ),
              ),
            ),
            SizedBox(width: 4.r),
            Icon(
              Symbols.expand_more_rounded,
              size: 16.r,
              color: scheme.onSurface.withValues(alpha: isFocused ? 0.9 : 0.4),
            ),
          ],
        ),
      ),
    );
  }
}

/// A row in the value picker used by searchable filter screens.
class SearchFilterMenuOption extends StatelessWidget {
  const SearchFilterMenuOption({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.symmetric(vertical: 2.r),
        padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 8.r),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primary.withValues(alpha: 0.18)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: isSelected ? scheme.primary : Colors.transparent,
            width: 2.r,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.r,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? scheme.primary : scheme.onSurface,
                ),
              ),
            ),
            if (isSelected)
              Icon(Symbols.check_rounded, size: 16.r, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

/// Keeps a filter picker clear of fixed chrome while allowing long lists.
class SearchFilterMenuLayout extends SingleChildLayoutDelegate {
  const SearchFilterMenuLayout({
    required this.topInset,
    required this.bottomInset,
  });

  final double topInset;
  final double bottomInset;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().copyWith(
        maxHeight: math.max(
          0.0,
          constraints.maxHeight - topInset - bottomInset,
        ),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset(
    (size.width - childSize.width) / 2,
    math.max((size.height - childSize.height) / 2, topInset),
  );

  @override
  bool shouldRelayout(SearchFilterMenuLayout oldDelegate) =>
      oldDelegate.topInset != topInset ||
      oldDelegate.bottomInset != bottomInset;
}
