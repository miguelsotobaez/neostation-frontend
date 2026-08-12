import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/global_notification_service.dart';
import 'package:neostation/themes/app_themes.dart';
import 'package:neostation/themes/corner_radii.dart';

/// Notification bell icon that opens a dropdown with all active global
/// notifications, including their progress.
///
/// Designed to live in the top header next to the clock.
///
/// The dropdown is rendered through an [OverlayEntry] (not `showMenu`) so the
/// notification list can rebuild live without `showMenu`'s `IntrinsicWidth`
/// choking on the shrink-wrapping list viewport.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  OverlayEntry? _overlayEntry;

  /// Vertical gap between the bell icon and the top of the dropdown.
  static const double _dropdownGap = 14;

  /// Inset of the dropdown from the right edge of the screen.
  static const double _dropdownRightInset = 8;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 0.4).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _pulseController.repeat(reverse: true);
  }

  @override
  void dispose() {
    _closeDropdown();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<GlobalNotificationData>>(
      valueListenable: GlobalNotificationService().notifier,
      builder: (context, notifications, _) {
        final hasNotifications = notifications.isNotEmpty;
        return GestureDetector(
          onTap: () => _toggleDropdown(context),
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Opacity(
                    opacity: hasNotifications ? _pulseAnimation.value : 1.0,
                    child: child,
                  );
                },
                child: Icon(
                  hasNotifications
                      ? Symbols.notifications_active_rounded
                      : Symbols.notifications_rounded,
                  color: hasNotifications
                      ? AppThemes.getCustomColors(context).warningColor
                      : Theme.of(context).colorScheme.onSurface,
                  size: 14.r,
                ),
              ),
              if (hasNotifications)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    width: 5.r,
                    height: 5.r,
                    decoration: BoxDecoration(
                      color: AppThemes.getCustomColors(context).warningColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Theme.of(context).colorScheme.surface,
                        width: 0.8.r,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _toggleDropdown(BuildContext context) {
    if (_overlayEntry != null) {
      _closeDropdown();
    } else {
      _openDropdown(context);
    }
  }

  void _openDropdown(BuildContext context) {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (overlayContext) {
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _closeDropdown,
              ),
            ),
            Positioned(
              top: offset.dy + size.height + _dropdownGap,
              right: _dropdownRightInset,
              child: const _NotificationsDropdownMenu(),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _closeDropdown() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

class _NotificationsDropdownMenu extends StatelessWidget {
  const _NotificationsDropdownMenu();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<GlobalNotificationData>>(
      valueListenable: GlobalNotificationService().notifier,
      builder: (context, notifications, _) {
        return Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 6,
          shadowColor: Theme.of(
            context,
          ).colorScheme.shadow.withValues(alpha: 0.3),
          shape: RoundedRectangleBorder(
            borderRadius: CornerRadii.of(context).radiusExternal,
            side: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outline.withValues(alpha: 0.3),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 300.r,
              minWidth: 200.r,
              maxHeight: 360.r,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: 12.r,
                    vertical: 10.r,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppLocale.notifications.getString(context),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 12.r,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (notifications.isNotEmpty)
                        GestureDetector(
                          onTap: () => GlobalNotificationService().dismiss(),
                          child: Text(
                            AppLocale.clearAll.getString(context),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 10.r,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (notifications.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(16.r),
                    child: Center(
                      child: Text(
                        AppLocale.noActiveNotifications.getString(context),
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onSurface.withValues(alpha: 0.6),
                          fontSize: 11.r,
                        ),
                      ),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: notifications.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1.r,
                        color: Theme.of(
                          context,
                        ).colorScheme.outline.withValues(alpha: 0.2),
                      ),
                      itemBuilder: (context, index) {
                        return _NotificationDropdownItem(
                          data: notifications[index],
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _NotificationDropdownItem extends StatelessWidget {
  final GlobalNotificationData data;

  const _NotificationDropdownItem({required this.data});

  @override
  Widget build(BuildContext context) {
    final Color iconColor;
    final IconData icon;

    switch (data.type) {
      case GlobalNotificationType.success:
        iconColor = Colors.green.shade400;
        icon = Symbols.check_circle_rounded;
      case GlobalNotificationType.error:
        iconColor = Theme.of(context).colorScheme.error;
        icon = Symbols.error_rounded;
      case GlobalNotificationType.info:
        iconColor = Theme.of(context).colorScheme.primary;
        icon = Symbols.info_rounded;
    }

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 10.r),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 16.r),
          SizedBox(width: 8.r),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (data.title != null)
                  Text(
                    data.title!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 11.r,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                Text(
                  data.message,
                  style: TextStyle(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.8),
                    fontSize: 10.r,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                if (data.progress != null) ...[
                  SizedBox(height: 6.r),
                  LinearProgressIndicator(
                    value: data.progress,
                    minHeight: 3.r,
                    color: iconColor,
                    backgroundColor: iconColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: 8.r),
          GestureDetector(
            onTap: () => GlobalNotificationService().dismiss(data.id),
            child: Icon(
              Symbols.close_rounded,
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.5),
              size: 14.r,
            ),
          ),
        ],
      ),
    );
  }
}
