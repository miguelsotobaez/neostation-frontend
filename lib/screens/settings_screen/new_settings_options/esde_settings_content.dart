import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:file_picker/file_picker.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/services/esde_import_service.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/services/permission_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/services/user_data_location_service.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/widgets/tv_directory_picker.dart';
import 'settings_title.dart';

/// Settings pane for importing metadata and fallback artwork from an ES-DE
/// (EmulationStation Desktop Edition) installation.
class EsdeSettingsContent extends StatefulWidget {
  final bool isContentFocused;
  final int selectedContentIndex;

  const EsdeSettingsContent({
    super.key,
    required this.isContentFocused,
    required this.selectedContentIndex,
  });

  @override
  State<EsdeSettingsContent> createState() => EsdeSettingsContentState();
}

class EsdeSettingsContentState extends State<EsdeSettingsContent> {
  static final _log = LoggerService.instance;

  // Navigable items: 0 = select folder, 1 = run import.
  static const int _itemSelectFolder = 0;
  static const int _itemRunImport = 1;

  bool _isImporting = false;
  double _importProgress = 0.0;
  String _importLabel = '';
  EsdeImportResult? _lastResult;

  int getItemCount() => 2;

  void selectItem(int index) {
    switch (index) {
      case _itemSelectFolder:
        _selectEsdeFolder();
        break;
      case _itemRunImport:
        _runImport();
        break;
    }
  }

  String get _currentPath {
    return context.read<SqliteConfigProvider>().config.esdeFolderPath;
  }

  // ---------------------------------------------------------------------------
  // Folder picker
  // ---------------------------------------------------------------------------

  Future<void> _selectEsdeFolder() async {
    try {
      String? selected;

      if (Platform.isAndroid) {
        final isTV = await PermissionService.isTelevision();
        if (!mounted) return;
        if (isTV) {
          selected = await TvDirectoryPicker.show(context);
        } else {
          try {
            final uri = await PermissionService.requestFolderAccess();
            if (uri != null) {
              final uriStr = uri.toString();
              final hasFiles = await PermissionService.hasAllFilesAccess();
              selected =
                  await UserDataLocationService.resolveAndroidUserDataPath(
                    uriStr,
                    hasAllFilesAccess: hasFiles,
                  ) ??
                  UserDataLocationService.safUriToRealPath(uriStr);
            }
          } on PlatformException catch (e) {
            if (e.code == 'PICKER_FAILED' && mounted) {
              selected = await TvDirectoryPicker.show(context);
            }
          }
        }
      } else {
        selected = await FilePicker.getDirectoryPath(
          dialogTitle: AppLocale.esdeSelectFolder.getString(context),
        );
      }

      if (selected == null || !mounted) return;
      if (selected.endsWith(Platform.pathSeparator)) {
        selected = selected.substring(0, selected.length - 1);
      }

      await context.read<SqliteConfigProvider>().updateEsdeFolderPath(selected);
      // Refresh the fallback map so any already-recorded systems resolve.
      if (mounted) {
        await context.read<FileProvider>().refreshEsde();
      }
      if (mounted) setState(() {});
    } catch (e) {
      _log.e('ES-DE folder selection failed: $e');
      if (mounted) {
        AppNotification.showNotification(
          context,
          '$e',
          type: NotificationType.error,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Import
  // ---------------------------------------------------------------------------

  Future<void> _runImport() async {
    final root = _currentPath;
    if (root.trim().isEmpty) {
      AppNotification.showNotification(
        context,
        AppLocale.esdeImportNoFolder.getString(context),
        type: NotificationType.info,
      );
      return;
    }
    if (_isImporting) return;

    setState(() {
      _isImporting = true;
      _importProgress = 0.0;
      _importLabel = '';
      _lastResult = null;
    });

    EsdeImportResult? result;
    String? error;
    try {
      result = await EsdeImportService.import(
        root,
        onProgress: (p, label) {
          if (mounted) {
            setState(() {
              _importProgress = p;
              _importLabel = label;
            });
          }
        },
      );
      // Rebuild the fallback map now that esde_media_dir rows exist.
      if (mounted) await context.read<FileProvider>().refreshEsde();
    } catch (e) {
      error = e.toString();
      _log.e('ES-DE import failed: $e');
    }

    if (!mounted) return;
    setState(() {
      _isImporting = false;
      _lastResult = result;
    });

    if (error != null) {
      AppNotification.showNotification(
        context,
        error,
        type: NotificationType.error,
      );
    } else if (result != null) {
      AppNotification.showNotification(
        context,
        '${AppLocale.esdeImportComplete.getString(context)}: '
        '${result.gamesImported} games, ${result.systemsMatched} systems',
        type: NotificationType.info,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  Widget _buildProgress(ThemeData theme) {
    if (!_isImporting) return const SizedBox.shrink();
    final pct = _importProgress;
    return Container(
      margin: EdgeInsets.only(bottom: 12.r),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.2),
          width: 1.r,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                AppLocale.esdeImporting.getString(context),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 10.r,
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                '${(pct * 100).toInt()}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 10.r,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.r),
          ClipRRect(
            borderRadius: BorderRadius.circular(4.r),
            child: LinearProgressIndicator(
              value: pct > 0 ? pct : null,
              minHeight: 6.r,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(
                theme.colorScheme.primary,
              ),
            ),
          ),
          if (_importLabel.isNotEmpty) ...[
            SizedBox(height: 4.r),
            Text(
              _importLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 9.r,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontFamily: 'monospace',
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultSummary(ThemeData theme) {
    final r = _lastResult;
    if (r == null || _isImporting) return const SizedBox.shrink();
    return Container(
      margin: EdgeInsets.only(bottom: 12.r),
      padding: EdgeInsets.all(12.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppLocale.esdeImportComplete.getString(context),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 11.r,
              color: theme.colorScheme.primary,
            ),
          ),
          SizedBox(height: 4.r),
          Text(
            'Systems matched: ${r.systemsMatched}   '
            'unmatched: ${r.systemsUnmatched}\n'
            'Games imported: ${r.gamesImported}   '
            'no ROM match: ${r.gamesUnmatched}\n'
            'Favorites / stats updated: ${r.statsUpdated}',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 9.5.r,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionRow(
    ThemeData theme, {
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailingBelow,
  }) {
    final isSelected =
        widget.isContentFocused && widget.selectedContentIndex == index;
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.outline.withValues(alpha: 0);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: borderColor, width: isSelected ? 2.r : 1.r),
      ),
      margin: EdgeInsets.only(bottom: 8.r),
      child: InkWell(
        onTap: () {
          SfxService().playNavSound();
          selectItem(index);
        },
        borderRadius: BorderRadius.circular(12.r),
        canRequestFocus: false,
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 8.r),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    icon,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                    size: 20.r,
                  ),
                  SizedBox(width: 12.r),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 12.r,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        SizedBox(height: 2.r),
                        Text(
                          subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface.withValues(
                              alpha: 0.6,
                            ),
                            fontSize: 9.r,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (trailingBelow != null) ...[
                SizedBox(height: 6.r),
                trailingBelow,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPathChip(ThemeData theme, String path) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.r, vertical: 4.r),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: Row(
        children: [
          Icon(
            Symbols.folder_rounded,
            size: 11.r,
            color: theme.colorScheme.primary.withValues(alpha: 0.5),
          ),
          SizedBox(width: 6.r),
          Expanded(
            child: Text(
              path,
              style: TextStyle(
                fontSize: 9.r,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                fontFamily: 'monospace',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Rebuild when config (path) changes.
    final path = context.watch<SqliteConfigProvider>().config.esdeFolderPath;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsTitle(
          title: AppLocale.esdeImport.getString(context),
          subtitle: AppLocale.esdeImportSubtitle.getString(context),
        ),
        SizedBox(height: 12.r),
        _buildProgress(theme),
        _buildResultSummary(theme),
        Expanded(
          child: ListView(
            physics: const ClampingScrollPhysics(),
            children: [
              _buildActionRow(
                theme,
                index: _itemSelectFolder,
                icon: Symbols.folder_special_rounded,
                title: AppLocale.esdeSelectFolder.getString(context),
                subtitle: AppLocale.esdeSelectFolderSubtitle.getString(context),
                trailingBelow: path.trim().isNotEmpty
                    ? _buildPathChip(theme, path)
                    : null,
              ),
              _buildActionRow(
                theme,
                index: _itemRunImport,
                icon: Symbols.download_rounded,
                title: AppLocale.esdeRunImport.getString(context),
                subtitle: AppLocale.esdeRunImportSubtitle.getString(context),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
