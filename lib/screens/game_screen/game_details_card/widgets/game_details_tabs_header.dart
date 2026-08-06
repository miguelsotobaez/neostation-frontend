import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/widgets/bumper_glyph.dart';

import '../../../../themes/corner_radii.dart';

/// Defines the navigable sections within the game details card.
enum DetailTab { wheel, box2d, screenshotVideo, gameInfo, achievements }

/// A navigation header component that manages tab switching and global card actions.
///
/// Features hardware-mapped bumper iconography (LB/RB) for intuitive gamepad
/// navigation and uses fluid animations for tab transitions. Dynamically adjusts
/// its layout based on the availability of metadata and system features.
class GameDetailsTabsHeader extends StatelessWidget {
  final bool isScreenshotVideoHidden;
  final bool hasRetroAchievements;
  final DetailTab currentTab;
  final ValueChanged<DetailTab> onTabChanged;

  const GameDetailsTabsHeader({
    super.key,
    required this.isScreenshotVideoHidden,
    required this.hasRetroAchievements,
    required this.currentTab,
    required this.onTabChanged,
  });

  /// Ordered list of always-visible tab enums.
  static const List<DetailTab> _baseTabs = [
    DetailTab.wheel,
    DetailTab.box2d,
    DetailTab.screenshotVideo,
    DetailTab.gameInfo,
  ];

  @override
  Widget build(BuildContext context) {
    // Dynamically calculate the active tab count for layout arbitration.
    final List<DetailTab> visibleTabs = [
      ..._baseTabs.where(
        (t) => t != DetailTab.screenshotVideo || !isScreenshotVideoHidden,
      ),
      if (hasRetroAchievements) DetailTab.achievements,
    ];

    final int numTabs = visibleTabs.length;
    final double tabWidth = 36.r;
    final double totalTabsWidth = numTabs * tabWidth;

    // Resolve the visual index for the cursor animation, accounting for hidden tabs.
    final int visualIndex = visibleTabs
        .indexOf(currentTab)
        .clamp(0, numTabs - 1);

    final theme = Theme.of(context);

    return ClipRRect(
      child: Container(
        height: 46.r,
        padding: EdgeInsets.only(top: 4.r, right: 8.r),
        child: Row(
          children: [
            const Spacer(),

            // Bumper glyphs sit outside the pill so the pill reads as a single
            // switch and the hardware hints stay visually distinct from it.
            const BumperGlyph(isLeft: true),
            SizedBox(width: 6.r),

            // Tab Navigation Group: Hardware-mapped navigation controls.
            Container(
              height: 36.r,
              padding: EdgeInsets.symmetric(horizontal: 8.r),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.9),
                borderRadius:
                    Theme.of(
                      context,
                    ).extension<CornerRadii>()?.radiusExternal ??
                    BorderRadius.circular(12.r),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                  width: 1.r,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(
                      context,
                    ).colorScheme.shadow.withValues(alpha: 0.1),
                    blurRadius: 4.r,
                    offset: Offset(2.0.r, 2.0.r),
                  ),
                ],
              ),
              child: SizedBox(
                width: totalTabsWidth,
                height: 36.r,
                child: Stack(
                  children: [
                    // Transition Cursor: Fluidly follows the active selection.
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeInOut,
                      left: visualIndex * tabWidth,
                      top: 4.r,
                      bottom: 4.r,
                      width: tabWidth,
                      child: Container(
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius:
                              Theme.of(
                                context,
                              ).extension<CornerRadii>()?.radiusInternal ??
                              BorderRadius.circular(14.r),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (final tab in visibleTabs)
                          _TabItem(
                            icon: _iconForTab(tab),
                            tab: tab,
                            width: tabWidth,
                            isSelected: currentTab == tab,
                            onTap: onTabChanged,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            SizedBox(width: 6.r),
            const BumperGlyph(isLeft: false),
          ],
        ),
      ),
    );
  }

  static IconData _iconForTab(DetailTab tab) {
    return switch (tab) {
      DetailTab.wheel => Symbols.gamepad_rounded,
      DetailTab.box2d => Symbols.widgets_rounded,
      DetailTab.screenshotVideo => Symbols.image_rounded,
      DetailTab.gameInfo => Symbols.description_rounded,
      DetailTab.achievements => Symbols.emoji_events_rounded,
    };
  }
}

/// An individual tab selector icon with click/tap handling.
class _TabItem extends StatelessWidget {
  final IconData icon;
  final DetailTab tab;
  final double width;
  final bool isSelected;
  final ValueChanged<DetailTab> onTap;

  const _TabItem({
    required this.icon,
    required this.tab,
    required this.width,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          SfxService().playNavSound();
          onTap(tab);
        },
        canRequestFocus: false,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: theme.colorScheme.onSurface.withValues(alpha: 0.1),
        child: Container(
          width: width,
          height: 36.r,
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18.r,
            color: isSelected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}
