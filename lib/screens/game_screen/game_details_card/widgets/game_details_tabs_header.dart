import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/services/sfx_service.dart';

import '../../../../themes/corner_radii.dart';

/// Defines the navigable sections within the game details card.
enum DetailTab { general, gameInfo, achievements }

/// A navigation header component that manages tab switching and global card actions.
///
/// Features hardware-mapped bumper iconography (LB/RB) for intuitive gamepad
/// navigation and uses fluid animations for tab transitions. Dynamically adjusts
/// its layout based on the availability of metadata and system features.
class GameDetailsTabsHeader extends StatelessWidget {
  final bool isGameInfoHidden;
  final bool hasRetroAchievements;
  final DetailTab currentTab;
  final ValueChanged<DetailTab> onTabChanged;

  const GameDetailsTabsHeader({
    super.key,
    required this.isGameInfoHidden,
    required this.hasRetroAchievements,
    required this.currentTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Dynamically calculate the active tab count for layout arbitration.
    int numTabs = 1; // General is always present.
    if (!isGameInfoHidden) numTabs++;
    if (hasRetroAchievements) numTabs++;

    final double tabWidth = 36.r;
    final double totalTabsWidth = numTabs * tabWidth;

    // Resolve the visual index for the cursor animation, accounting for hidden tabs.
    int visualIndex = 0;
    if (currentTab == DetailTab.gameInfo) {
      visualIndex = 1;
    } else if (currentTab == DetailTab.achievements) {
      visualIndex = isGameInfoHidden ? 1 : 2;
    }

    final theme = Theme.of(context);

    return ClipRRect(
      child: Container(
        height: 46.r,
        padding: EdgeInsets.only(top: 4.r, right: 8.r),
        child: Row(
          children: [
            const Spacer(),

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
              child: ClipRRect(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/gamepad/Xbox_LB_bumper.png',
                      width: 22.r,
                      height: 22.r,
                      color: theme.colorScheme.onSurface,
                    ),
                    SizedBox(width: 4.r),
                    SizedBox(
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
                                    Theme.of(context)
                                        .extension<CornerRadii>()
                                        ?.radiusInternal ??
                                    BorderRadius.circular(14.r),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              _TabItem(
                                icon: Symbols.gamepad_rounded,
                                tab: DetailTab.general,
                                width: tabWidth,
                                isSelected: currentTab == DetailTab.general,
                                onTap: onTabChanged,
                              ),
                              if (!isGameInfoHidden)
                                _TabItem(
                                  icon: Symbols.image_rounded,
                                  tab: DetailTab.gameInfo,
                                  width: tabWidth,
                                  isSelected: currentTab == DetailTab.gameInfo,
                                  onTap: onTabChanged,
                                ),
                              if (hasRetroAchievements)
                                _TabItem(
                                  icon: Symbols.emoji_events_rounded,
                                  tab: DetailTab.achievements,
                                  width: tabWidth,
                                  isSelected:
                                      currentTab == DetailTab.achievements,
                                  onTap: onTabChanged,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    SizedBox(width: 4.r),
                    Image.asset(
                      'assets/images/gamepad/Xbox_RB_bumper.png',
                      width: 22.r,
                      height: 22.r,
                      color: theme.colorScheme.onSurface,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
