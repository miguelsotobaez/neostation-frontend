import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/collection_model.dart';
import 'package:neostation/services/sfx_service.dart';

/// Card widget representing a single collection or the "+ Create Collection" action.
class CollectionCard extends StatelessWidget {
  final CollectionModel? collection;
  final bool isCreateCard;
  final bool isFocused;
  final VoidCallback? onTap;
  final VoidCallback? onOptions;

  const CollectionCard({
    super.key,
    this.collection,
    this.isCreateCard = false,
    this.isFocused = false,
    this.onTap,
    this.onOptions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final primaryColor = colorScheme.primary;

    if (isCreateCard) {
      return _buildCreateCard(context, theme, primaryColor);
    }

    return _buildCollectionCard(context, theme, primaryColor);
  }

  Widget _buildCollectionCard(
    BuildContext context,
    ThemeData theme,
    Color primaryColor,
  ) {
    final col = collection!;
    final countText = col.romCount == 1
        ? '$col.romCount game'
        : '$col.romCount games';

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          SfxService().playEnterSound();
          onTap?.call();
        },
        onLongPress: () {
          SfxService().playEnterSound();
          onOptions?.call();
        },
        child: AnimatedScale(
          scale: isFocused ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isFocused
                  ? theme.cardColor.withValues(alpha: 0.95)
                  : theme.cardColor.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: isFocused
                    ? primaryColor
                    : theme.dividerColor.withValues(alpha: 0.3),
                width: isFocused ? 2.5.r : 1.r,
              ),
              boxShadow: isFocused
                  ? [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.35),
                        blurRadius: 18.r,
                        spreadRadius: 2.r,
                      ),
                    ]
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 8.r,
                        offset: const Offset(0, 4),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15.r),
              child: Stack(
                children: [
                  // Accent color top banner strip
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 6.r,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            primaryColor,
                            primaryColor.withValues(alpha: 0.6),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.all(18.r),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: EdgeInsets.all(10.r),
                              decoration: BoxDecoration(
                                color: isFocused
                                    ? primaryColor.withValues(alpha: 0.2)
                                    : primaryColor.withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Symbols.collections_bookmark_rounded,
                                size: 26.r,
                                color: primaryColor,
                              ),
                            ),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10.w,
                                vertical: 4.h,
                              ),
                              decoration: BoxDecoration(
                                color: primaryColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12.r),
                                border: Border.all(
                                  color: primaryColor.withValues(alpha: 0.3),
                                  width: 1.r,
                                ),
                              ),
                              child: Text(
                                countText,
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          col.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                            color: isFocused
                                ? primaryColor
                                : theme.textTheme.bodyLarge?.color,
                          ),
                        ),
                        if (col.description != null &&
                            col.description!.isNotEmpty) ...[
                          SizedBox(height: 4.h),
                          Text(
                            col.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.sp,
                              color: theme.textTheme.bodyMedium?.color
                                  ?.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCreateCard(
    BuildContext context,
    ThemeData theme,
    Color primaryColor,
  ) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          SfxService().playEnterSound();
          onTap?.call();
        },
        child: AnimatedScale(
          scale: isFocused ? 1.04 : 1.0,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isFocused
                  ? primaryColor.withValues(alpha: 0.12)
                  : theme.cardColor.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(
                color: isFocused
                    ? primaryColor
                    : primaryColor.withValues(alpha: 0.4),
                width: isFocused ? 2.5.r : 1.5.r,
              ),
              boxShadow: isFocused
                  ? [
                      BoxShadow(
                        color: primaryColor.withValues(alpha: 0.3),
                        blurRadius: 18.r,
                        spreadRadius: 2.r,
                      ),
                    ]
                  : [],
            ),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(12.r),
                    decoration: BoxDecoration(
                      color: primaryColor.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Symbols.add_rounded,
                      size: 32.r,
                      color: primaryColor,
                    ),
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    AppLocale.createCollection.getString(context),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: primaryColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
