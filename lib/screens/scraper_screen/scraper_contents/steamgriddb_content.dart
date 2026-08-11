import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/repositories/steamgriddb_repository.dart';
import 'package:neostation/services/steamgriddb_service.dart';
import 'package:neostation/services/global_notification_service.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/providers/sqlite_database_provider.dart';
import 'package:provider/provider.dart';

/// SteamGridDB settings + scrape trigger: a standalone artwork-only source,
/// independent of ScreenScraper's account/region/language/systems config.
///
/// Auth is a single free personal API key (steamgriddb.com/profile/preferences/api)
/// rather than a login, so this combines what would otherwise be a separate
/// "Account" + "Scraping" pair into one panel.
class SteamGridDbContent extends StatefulWidget {
  final bool isContentFocused;
  final int selectedContentIndex;

  const SteamGridDbContent({
    super.key,
    required this.isContentFocused,
    required this.selectedContentIndex,
  });

  @override
  State<SteamGridDbContent> createState() => SteamGridDbContentState();

  /// Number of gamepad-navigable items: key field, save/clear, start scrape.
  static int get itemCount => 3;
}

class SteamGridDbContentState extends State<SteamGridDbContent> {
  static final _log = LoggerService.instance;
  static const _notificationId = 'steamgriddb_scraping_progress';

  final TextEditingController _keyController = TextEditingController();
  final FocusNode _keyFocus = FocusNode();
  bool _obscureKey = true;
  bool _hasKey = false;
  bool _isSaving = false;
  bool _isScraping = false;
  int _processed = 0;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _loadKey();
  }

  @override
  void dispose() {
    _keyController.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    final key = await SteamGridDbRepository.getApiKey();
    if (!mounted) return;
    setState(() {
      _hasKey = key != null;
      _keyController.text = key ?? '';
    });
  }

  void selectItem(int index) {
    switch (index) {
      case 0:
        _keyFocus.requestFocus();
        break;
      case 1:
        if (_hasKey) {
          _clearKey();
        } else {
          _saveKey();
        }
        break;
      case 2:
        if (_isScraping) {
          _stopScraping();
        } else if (_hasKey) {
          _startScraping();
        }
        break;
    }
  }

  Future<void> _saveKey() async {
    final key = _keyController.text.trim();
    if (key.isEmpty) {
      AppNotification.showNotification(
        context,
        AppLocale.pleaseCompleteAllFields.getString(context),
        type: NotificationType.error,
      );
      return;
    }

    setState(() => _isSaving = true);
    final valid = await SteamGridDbService.validateApiKey(key);
    if (!mounted) return;

    if (!valid) {
      setState(() => _isSaving = false);
      AppNotification.showNotification(
        context,
        AppLocale.steamGridDbInvalidKey.getString(context),
        type: NotificationType.error,
      );
      return;
    }

    await SteamGridDbRepository.saveApiKey(key);
    if (!mounted) return;
    setState(() {
      _isSaving = false;
      _hasKey = true;
    });
    AppNotification.showNotification(
      context,
      AppLocale.steamGridDbKeySaved.getString(context),
      type: NotificationType.success,
    );
  }

  Future<void> _clearKey() async {
    await SteamGridDbRepository.clearApiKey();
    if (!mounted) return;
    setState(() {
      _hasKey = false;
      _keyController.clear();
    });
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
      final count = await SteamGridDbService.scrapeAll(
        provider: context.read<SqliteDatabaseProvider>(),
        onProgress: (processed, total) {
          if (!mounted) return;
          setState(() {
            _processed = processed;
            _total = total;
          });
          if (!_isScraping) return; // stopped by the user mid-run
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
      _log.e('SteamGridDB: scraping run failed', error: e);
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
    // scrapeAll checks nothing external to cancel mid-loop today; flipping
    // this flag stops the *reporting* immediately and the loop itself drains
    // quickly since each step is a single network round-trip.
    setState(() => _isScraping = false);
  }

  Future<void> _openApiKeyPage() async {
    final uri = Uri.parse(
      'https://www.steamgriddb.com/profile/preferences/api',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocale.steamGridDbDescription.getString(context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              fontSize: 11.sp,
            ),
          ),
          SizedBox(height: 12.h),
          _buildKeyField(theme),
          SizedBox(height: 8.h),
          GestureDetector(
            onTap: _openApiKeyPage,
            child: Text(
              AppLocale.steamGridDbGetKey.getString(context),
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 11.sp,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
          SizedBox(height: 16.h),
          _buildActionButton(
            theme,
            index: 1,
            icon: _hasKey
                ? Symbols.delete_outline_rounded
                : Symbols.save_rounded,
            label:
                (_hasKey
                        ? AppLocale.steamGridDbClearKey
                        : AppLocale.steamGridDbSaveKey)
                    .getString(context),
            onTap: _hasKey ? _clearKey : _saveKey,
            loading: _isSaving,
            destructive: _hasKey,
          ),
          SizedBox(height: 12.h),
          _buildActionButton(
            theme,
            index: 2,
            icon: _isScraping
                ? Symbols.stop_circle_rounded
                : Symbols.download_rounded,
            label: _isScraping
                ? '${AppLocale.scrapingInProgress.getString(context)} ($_processed/$_total)'
                : AppLocale.steamGridDbStartScraping.getString(context),
            onTap: _hasKey || _isScraping
                ? (_isScraping ? _stopScraping : _startScraping)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildKeyField(ThemeData theme) {
    final focused = widget.isContentFocused && widget.selectedContentIndex == 0;
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(
          color: focused
              ? theme.colorScheme.primary
              : theme.colorScheme.primary.withValues(alpha: 0.15),
          width: focused ? 2.r : 1.r,
        ),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12.r),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _keyController,
              focusNode: _keyFocus,
              obscureText: _obscureKey,
              style: TextStyle(fontSize: 13.sp),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: AppLocale.steamGridDbApiKeyHint.getString(context),
                hintStyle: TextStyle(
                  fontSize: 13.sp,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
              onSubmitted: (_) => _saveKey(),
            ),
          ),
          IconButton(
            icon: Icon(
              _obscureKey
                  ? Symbols.visibility_rounded
                  : Symbols.visibility_off_rounded,
              size: 18.r,
            ),
            onPressed: () => setState(() => _obscureKey = !_obscureKey),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    ThemeData theme, {
    required int index,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    bool loading = false,
    bool destructive = false,
  }) {
    final focused =
        widget.isContentFocused && widget.selectedContentIndex == index;
    final color = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.r, vertical: 12.r),
        decoration: BoxDecoration(
          color: color.withValues(alpha: focused ? 0.18 : 0.1),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(
            color: focused ? color : color.withValues(alpha: 0.25),
            width: focused ? 2.r : 1.r,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading)
              SizedBox(
                width: 16.r,
                height: 16.r,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Icon(
                icon,
                size: 18.r,
                color: onTap == null ? color.withValues(alpha: 0.4) : color,
              ),
            SizedBox(width: 10.r),
            Text(
              label,
              style: TextStyle(
                color: onTap == null ? color.withValues(alpha: 0.4) : color,
                fontWeight: FontWeight.w600,
                fontSize: 12.sp,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
