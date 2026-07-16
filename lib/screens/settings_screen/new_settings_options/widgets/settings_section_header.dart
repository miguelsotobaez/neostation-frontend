import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Section divider used to group settings rows under a labelled heading.
///
/// Renders a short primary-colour accent bar followed by an uppercase-weight
/// label. Shared by any settings content panel that groups its rows into
/// sections (Directories, Secondary).
class SettingsSectionHeader extends StatelessWidget {
  /// Heading text shown beside the accent bar.
  final String label;

  const SettingsSectionHeader({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: 8.r, top: 4.r, left: 2.r),
      child: Row(
        children: [
          Container(
            width: 3.r,
            height: 14.r,
            decoration: BoxDecoration(
              color: theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2.r),
            ),
          ),
          SizedBox(width: 8.r),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.r,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
