import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/howlongtobeat_service.dart';
import 'package:neostation/services/global_notification_service.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/providers/sqlite_database_provider.dart';
import 'package:provider/provider.dart';

/// HowLongToBeat scrape trigger: a completion-time-estimate source,
/// independent of ScreenScraper. No account or API key — HowLongToBeat has
/// no official API, so this talks to the same public search endpoint the
/// site itself uses.
class HowLongToBeatContent extends StatefulWidget {
  final bool isContentFocused;
  final int selectedContentIndex;

  const HowLongToBeatContent({
    super.key,
    required this.isContentFocused,
    required this.selectedContentIndex,
  });

  @override
  State<HowLongToBeatContent> createState() => HowLongToBeatContentState();

  /// Number of gamepad-navigable items: just the start-scrape action.
  static int get itemCount => 1;
}

class HowLongToBeatContentState extends State<HowLongToBeatContent> {
  static final _log = LoggerService.instance;
  static const _notificationId = 'hltb_scraping_progress';

  bool _isScraping = false;
  int _processed = 0;
  int _total = 0;

  void selectItem(int index) {
    if (index == 0) {
      if (_isScraping) {
        _stopScraping();
      } else {
        _startScraping();
      }
    }
  }

  Future<void> _startScraping() async {
    setState(() {
      _isScraping = true;
      _processed = 0;
      _total = 0;
    });

    final localeInProgress = AppLocale.scrapingInProgress.getString(context);
    final localeCompleted = AppLocale.scrapingCompleted.getString(context);
    final localeCancelled = AppLocale.scrapingCancelled.getString(context);
    final localeAllUpToDate = AppLocale.allGamesUpToDate.getString(context);

    GlobalNotificationService().show(
      id: _notificationId,
      message: localeInProgress,
      type: GlobalNotificationType.info,
      progress: 0,
    );

    try {
      final count = await HowLongToBeatService.scrapeAll(
        provider: context.read<SqliteDatabaseProvider>(),
        onProgress: (processed, total) {
          if (!mounted) return;
          setState(() {
            _processed = processed;
            _total = total;
          });
          if (!_isScraping) return;
          GlobalNotificationService().update(
            id: _notificationId,
            message: '$localeInProgress ($processed/$total)',
            type: GlobalNotificationType.info,
            progress: total > 0 ? processed / total : null,
          );
        },
      );

      if (!mounted) return;
      if (!_isScraping) {
        GlobalNotificationService().update(
          id: _notificationId,
          message: localeCancelled,
          type: GlobalNotificationType.info,
          progress: null,
        );
      } else {
        GlobalNotificationService().update(
          id: _notificationId,
          message: count > 0 ? '$localeCompleted ($count)' : localeAllUpToDate,
          type: GlobalNotificationType.success,
          progress: null,
        );
      }
    } catch (e) {
      _log.e('HowLongToBeat: scraping run failed', error: e);
      if (mounted) {
        GlobalNotificationService().update(
          id: _notificationId,
          message: AppLocale.metadataError.getString(context),
          type: GlobalNotificationType.error,
          progress: null,
        );
      }
    } finally {
      if (mounted) setState(() => _isScraping = false);
    }
  }

  void _stopScraping() {
    setState(() => _isScraping = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final focused = widget.isContentFocused && widget.selectedContentIndex == 0;
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocale.hltbDescription.getString(context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 11.sp,
            ),
          ),
          SizedBox(height: 16.h),
          GestureDetector(
            onTap: _isScraping ? _stopScraping : _startScraping,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16.r, vertical: 12.r),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(
                  alpha: focused ? 0.18 : 0.1,
                ),
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(
                  color: focused
                      ? theme.colorScheme.primary
                      : theme.colorScheme.primary.withValues(alpha: 0.25),
                  width: focused ? 2.r : 1.r,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isScraping
                        ? Symbols.stop_circle_rounded
                        : Symbols.download_rounded,
                    size: 18.r,
                    color: theme.colorScheme.primary,
                  ),
                  SizedBox(width: 10.r),
                  Text(
                    _isScraping
                        ? '${AppLocale.scrapingInProgress.getString(context)} ($_processed/$_total)'
                        : AppLocale.hltbStartScraping.getString(context),
                    style: TextStyle(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 12.sp,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
