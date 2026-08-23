import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../themes/corner_radii.dart';

/// Left-hand label of a split-layout [CoreFooter]: a rounded pill carrying the
/// focused item's name, with an optional count chip beside it.
///
/// Extracted from the systems grid/carousel footer so the RomM browser can wear
/// the same label rather than hand-rolling a second one.
class FooterLabelPill extends StatelessWidget {
  /// Name of the focused item (system, platform, collection…).
  final String label;

  /// Optional chip on the right of the pill (e.g. "128 games"); hidden when null.
  final String? countText;

  const FooterLabelPill({super.key, required this.label, this.countText});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radii = theme.extension<CornerRadii>();

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.only(top: 4.r, bottom: 4.r, left: 12.r, right: 6.r),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryFixed,
          borderRadius: radii?.radiusExternal ?? BorderRadius.circular(24.r),
          boxShadow: [
            BoxShadow(
              color: theme.colorScheme.shadow.withValues(alpha: 0.3),
              blurRadius: 3.r,
              offset: Offset(2.0.r, 2.0.r),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  color: theme.colorScheme.onTertiaryFixed,
                  fontSize: 14.r,
                  fontWeight: FontWeight.bold,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (countText != null) ...[
              SizedBox(width: 10.r),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 2.r),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius:
                      radii?.radiusInternal ?? BorderRadius.circular(12.r),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.shadow.withValues(alpha: 0.3),
                      blurRadius: 3.r,
                      offset: Offset(2.0.r, 2.0.r),
                    ),
                  ],
                ),
                child: Text(
                  countText!,
                  style: TextStyle(
                    color: theme.colorScheme.onSurface,
                    fontSize: 10.r,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5.r,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
