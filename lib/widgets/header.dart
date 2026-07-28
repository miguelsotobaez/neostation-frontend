import 'package:flutter/material.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:io';
import 'package:neostation/providers/theme_provider.dart';
import 'package:neostation/responsive.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/themes/app_themes.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/services/permission_service.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/widgets/header_sort_dropdown.dart';
import 'package:neostation/screens/app_screen.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/utils/time_format.dart';
import 'package:flutter_localization/flutter_localization.dart';

import '../themes/corner_radii.dart';

class Header extends StatefulWidget {
  final int selectedTabIndex;
  final Function(int) onTabSelected;

  const Header({
    super.key,
    required this.selectedTabIndex,
    required this.onTabSelected,
  });

  @override
  HeaderState createState() => HeaderState();
}

class HeaderState extends State<Header> {
  final Battery _battery = Battery();
  int _batteryLevel = 100;
  BatteryState? _batteryState;
  StreamSubscription<BatteryState>? _batteryStateSubscription;
  bool _isTelevision = false;
  DateTime _now = DateTime.now();
  Timer? _timeUpdateTimer;
  late final List<FocusNode> _tabFocusNodes;

  @override
  void initState() {
    super.initState();
    _tabFocusNodes = List.generate(
      AppTabs.count,
      (_) => FocusNode(skipTraversal: true),
    );
    _getBatteryLevel();
    _listenToBatteryState();
    _updateTime();
    _startTimeUpdateTimer();
    if (Platform.isAndroid) {
      PermissionService.isTelevision().then((isTV) {
        if (mounted && isTV) setState(() => _isTelevision = true);
      });
    }
  }

  @override
  void dispose() {
    _timeUpdateTimer?.cancel();
    _batteryStateSubscription?.cancel();
    for (final node in _tabFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  /// Subscribes to real-time battery state changes (charging/discharging/full).
  void _listenToBatteryState() {
    try {
      _batteryStateSubscription = _battery.onBatteryStateChanged.listen((
        state,
      ) {
        if (mounted) {
          setState(() => _batteryState = state);
        }
      });
    } catch (_) {
      // Some platforms don't expose battery state; ignore silently.
    }
  }

  void _updateTime() {
    if (mounted) {
      setState(() {
        _now = DateTime.now();
      });
      // Also update battery every minute
      _getBatteryLevel();
    }
  }

  void _startTimeUpdateTimer() {
    // Calculate how many seconds remain until the next minute
    final now = DateTime.now();
    final secondsUntilNextMinute = 60 - now.second;

    // Create initial timer that fires at the start of the next minute
    Future.delayed(Duration(seconds: secondsUntilNextMinute), () {
      if (mounted) {
        _updateTime();
        // Then create a periodic timer every 60 seconds
        _timeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
          if (mounted) {
            _updateTime();
          } else {
            timer.cancel();
          }
        });
      }
    });
  }

  Future<void> _getBatteryLevel() async {
    try {
      final level = await _battery.batteryLevel;
      if (mounted) {
        setState(() {
          // On Linux, 0% often indicates no battery (desktop), so we treat it as such
          if (Platform.isLinux && level == 0) {
            _batteryLevel = -1;
          } else {
            _batteryLevel = level;
          }
        });
      }
    } catch (e) {
      // Fallback for devices without battery (e.g., desktops)
      if (mounted) {
        setState(() {
          _batteryLevel = -1; // Indicate no battery
        });
      }
    }
  }

  /// Resolves the appropriate Material Symbols battery icon based on charge
  /// level and charging state.
  IconData _getBatteryIconData() {
    final isCharging =
        _batteryState == BatteryState.charging ||
        _batteryState == BatteryState.full;

    if (_batteryLevel == -1 || isCharging) {
      return Symbols.battery_android_frame_bolt;
    }

    if (_batteryLevel >= 90) return Symbols.battery_full;
    if (_batteryLevel >= 75) return Symbols.battery_android_frame_6;
    if (_batteryLevel >= 60) return Symbols.battery_android_frame_5;
    if (_batteryLevel >= 45) return Symbols.battery_android_frame_4;
    if (_batteryLevel >= 30) return Symbols.battery_android_frame_3;
    if (_batteryLevel >= 15) return Symbols.battery_android_frame_2;
    return Symbols.battery_android_frame_1;
  }

  Color _getBatteryColor(dynamic customColors) {
    if (_batteryLevel == -1) {
      return customColors.batteryPower;
    }
    if (_batteryLevel > 20) {
      return customColors.batteryFull;
    } else if (_batteryLevel > 5) {
      return customColors.batteryMedium;
    } else {
      return customColors.batteryLow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final customColors = AppThemes.getCustomColors(context);
    // Soft horizontal gradient derived from headerColors.background (left->right)

    return Consumer2<ThemeProvider, SqliteConfigProvider>(
      builder: (context, themeProvider, configProvider, child) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.transparent,
            border: Border.all(color: Colors.transparent, width: 0.r),
          ),
          height: 46.r,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (widget.selectedTabIndex == AppTabs.systems)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [HeaderSortDropdown()],
                  ),
                ),

              // Grouped Tab Navigation with Background (Glass Style)
              Align(
                key: const ValueKey('tabs-container'),
                alignment: Alignment.center,
                child: Container(
                  height: 32.r,
                  padding: EdgeInsets.symmetric(horizontal: 2.r),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                      width: 1.r,
                    ),
                    borderRadius:
                        Theme.of(
                          context,
                        ).extension<CornerRadii>()?.radiusExternal ??
                        BorderRadius.circular(8.r),
                    // normal black shadow
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // LB button (left)
                      _buildShoulderButton('LB', true),
                      // Tabs Section
                      Stack(
                        children: [
                          // Moving indicator
                          AnimatedPositioned(
                            left: widget.selectedTabIndex * 32.r,
                            top: 4.r,
                            bottom: 4.r,
                            width: 32.r,
                            duration: const Duration(milliseconds: 160),
                            curve: Curves.easeInOut,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius:
                                    Theme.of(context)
                                        .extension<CornerRadii>()
                                        ?.radiusInternal ??
                                    BorderRadius.circular(4.r),
                              ),
                            ),
                          ),
                          // Tab buttons
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 32.r,
                                height: 32.r,
                                child: _buildTabButton(
                                  context,
                                  AppTabs.systems,
                                  "assets/images/icons/grids.webp",
                                  AppLocale.systems.getString(context),
                                ),
                              ),
                              SizedBox(
                                width: 32.r,
                                height: 32.r,
                                child: _buildTabButton(
                                  context,
                                  AppTabs.search,
                                  null,
                                  AppLocale.searchTitle.getString(context),
                                  iconData: Symbols.search_rounded,
                                ),
                              ),
                              SizedBox(
                                width: 32.r,
                                height: 32.r,
                                child: _buildTabButton(
                                  context,
                                  AppTabs.sync,
                                  "assets/images/icons/cloud-add.webp",
                                  'Sync',
                                ),
                              ),
                              SizedBox(
                                width: 32.r,
                                height: 32.r,
                                child: _buildTabButton(
                                  context,
                                  AppTabs.achievements,
                                  "assets/images/icons/enhance-prize.webp",
                                  AppLocale.achievements.getString(context),
                                ),
                              ),
                              SizedBox(
                                width: 32.r,
                                height: 32.r,
                                child: _buildTabButton(
                                  context,
                                  AppTabs.scraper,
                                  "assets/images/icons/box-search.webp",
                                  AppLocale.scraping.getString(context),
                                ),
                              ),
                              SizedBox(
                                width: 32.r,
                                height: 32.r,
                                child: _buildTabButton(
                                  context,
                                  AppTabs.settings,
                                  "assets/images/icons/setting.webp",
                                  AppLocale.settings.getString(context),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      // RB button (right)
                      _buildShoulderButton('RB', false),
                    ],
                  ),
                ),
              ),

              // Steam-style system info
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  margin: EdgeInsets.only(right: 8.r),
                  padding: EdgeInsets.symmetric(
                    horizontal: 10.r,
                    vertical: 4.r,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                      width: 1.r,
                    ),
                    borderRadius:
                        Theme.of(
                          context,
                        ).extension<CornerRadii>()?.radiusExternal ??
                        BorderRadius.circular(14),
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
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Symbols.schedule,
                        color: Theme.of(context).colorScheme.onSurface,
                        size: 14.r,
                      ),
                      SizedBox(width: 4.r),
                      Text(
                        formatClockTime(
                          _now,
                          use12Hour: configProvider.config.use12HourClock,
                        ),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 12.r,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.3.r,
                        ),
                      ),
                      if (_batteryLevel != -1 &&
                          !_isTelevision &&
                          !Responsive.isHandheldXS(context)) ...[
                        SizedBox(width: 12.r),
                        Icon(
                          _getBatteryIconData(),
                          color: _getBatteryColor(customColors),
                          size: 16.r,
                        ),
                        SizedBox(width: 4.r),
                        Text(
                          "$_batteryLevel%",
                          style: TextStyle(
                            color: _getBatteryColor(customColors),
                            fontSize: 12.r,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.3.r,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Steam-style tab button.
  //
  // Most tabs use a webp asset; [iconData] is the fallback for tabs with no
  // matching asset (Search), rendered at the same box size and tint.
  Widget _buildTabButton(
    BuildContext context,
    int tabIndex,
    String? icon,
    String label, {
    IconData? iconData,
  }) {
    final bool isSelected = tabIndex == widget.selectedTabIndex;
    final Color tint = isSelected
        ? Theme.of(context).colorScheme.onPrimary
        : Theme.of(context).colorScheme.onSurface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        canRequestFocus: false,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        focusNode: _tabFocusNodes[tabIndex],
        splashColor: Colors.transparent,
        onTap: () {
          SfxService().playNavSound();
          widget.onTabSelected(tabIndex);
        },
        child: Container(
          padding: EdgeInsets.all(8.r),
          child: iconData != null
              ? Icon(iconData, size: 16.r, color: tint)
              : Image.asset(icon!, color: tint),
        ),
      ),
    );
  }

  // Steam-style shoulder button (LB/RB)
  Widget _buildShoulderButton(String label, bool isLeft) {
    final iconPath = isLeft
        ? 'assets/images/gamepad/Xbox_LB_bumper.png'
        : 'assets/images/gamepad/Xbox_RB_bumper.png';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.r, vertical: 2.r),
      child: SizedBox(
        width: 24.r,
        height: 24.r,
        child: Image.asset(
          iconPath,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      ),
    );
  }
}
