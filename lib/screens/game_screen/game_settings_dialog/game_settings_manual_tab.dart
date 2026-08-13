import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../l10n/app_locale.dart';
import '../../../models/game_model.dart';
import '../../../models/system_model.dart';
import '../../../providers/file_provider.dart';
import '../../../repositories/system_repository.dart';
import '../../../services/logger_service.dart';
import '../../../services/screenscraper_service.dart';
import '../../../services/sfx_service.dart';
import '../../../widgets/confirm_action_dialog.dart';
import '../../../widgets/custom_notification.dart';
import '../game_manual_reader_screen.dart';

/// Game Settings tab for locally cached ScreenScraper PDF manuals.
///
/// Manual scraping is optional globally, but this tab can always request the
/// selected game's manual explicitly. Reading is fully offline after download.
class GameSettingsManualTab extends StatefulWidget {
  final GameModel game;
  final SystemModel system;
  final FileProvider fileProvider;
  final bool isAllMode;

  const GameSettingsManualTab({
    super.key,
    required this.game,
    required this.system,
    required this.fileProvider,
    required this.isAllMode,
  });

  @override
  State<GameSettingsManualTab> createState() => GameSettingsManualTabState();
}

class GameSettingsManualTabState extends State<GameSettingsManualTab> {
  static final _log = LoggerService.instance;

  bool _isLoading = true;
  bool _isDownloading = false;
  bool _manualExists = false;
  String? _manualPath;
  int _selectedIndex = 0;
  double _downloadProgress = 0;

  String get _folder => widget.isAllMode && widget.game.systemFolderName != null
      ? widget.game.systemFolderName!
      : widget.system.primaryFolderName;

  int get _actionCount => _manualExists ? 3 : 1;

  @override
  void initState() {
    super.initState();
    _refreshManualState();
  }

  Future<void> _refreshManualState() async {
    final candidate = widget.game.getManualPath(_folder, widget.fileProvider);
    final exists = await File(candidate).exists();
    if (!mounted) return;
    setState(() {
      _manualPath = candidate;
      _manualExists = exists;
      _isLoading = false;
      _selectedIndex = _selectedIndex.clamp(0, _actionCount - 1);
    });
  }

  Future<SystemModel> _resolveTargetSystem() async {
    if (widget.isAllMode && widget.game.systemFolderName != null) {
      final original = await SystemRepository.getSystemByFolderName(
        widget.game.systemFolderName!,
      );
      if (original != null) return original;
    }
    return widget.system;
  }

  Future<void> _downloadManual({bool forceOverwrite = false}) async {
    if (_isDownloading) return;
    final romPath = widget.game.romPath;
    if (romPath == null) return;

    final targetSystem = await _resolveTargetSystem();
    final systemId = targetSystem.id;
    if (systemId == null) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0;
    });

    try {
      final result = await ScreenScraperService.downloadGameManual(
        appSystemId: systemId,
        romName: widget.game.romname,
        systemFolder: targetSystem.primaryFolderName,
        romPath: romPath,
        gameName: widget.game.name,
        forceOverwrite: forceOverwrite,
        onProgress: (status, progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );

      if (!mounted) return;
      final success = result['success'] == true;
      final messageKey = result['message']?.toString() ??
          (success ? AppLocale.manualDownloaded : AppLocale.manualDownloadFailed);
      AppNotification.showNotification(
        context,
        messageKey.getString(context),
        type: success ? NotificationType.success : NotificationType.error,
      );
      await _refreshManualState();
    } catch (e) {
      _log.e('Manual download failed: $e');
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.manualDownloadFailed.getString(context),
          type: NotificationType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloading = false);
    }
  }

  Future<void> _readManual() async {
    final manualPath = _manualPath;
    if (!_manualExists || manualPath == null) return;
    final displayName = widget.game.name.isNotEmpty
        ? widget.game.name
        : widget.game.romname;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameManualReaderScreen(
          manualPath: manualPath,
          gameTitle: displayName,
        ),
      ),
    );
  }

  Future<void> _deleteManual() async {
    final manualPath = _manualPath;
    if (!_manualExists || manualPath == null) return;

    final confirmed = await ConfirmActionDialog.show(
      context,
      title: AppLocale.deleteManual.getString(context),
      body: AppLocale.deleteManualConfirmation.getString(context),
      confirmLabel: AppLocale.delete.getString(context),
      icon: Symbols.delete_rounded,
    );
    if (!confirmed) return;

    try {
      final file = File(manualPath);
      if (await file.exists()) await file.delete();
      if (!mounted) return;
      AppNotification.showNotification(
        context,
        AppLocale.manualDeleted.getString(context),
        type: NotificationType.success,
      );
      await _refreshManualState();
    } catch (e) {
      _log.e('Could not delete manual: $e');
    }
  }

  bool moveUp() {
    if (_isDownloading) return false;
    final next = (_selectedIndex - 1).clamp(0, _actionCount - 1);
    if (next == _selectedIndex) return false;
    setState(() => _selectedIndex = next);
    return true;
  }

  bool moveDown() {
    if (_isDownloading) return false;
    final next = (_selectedIndex + 1).clamp(0, _actionCount - 1);
    if (next == _selectedIndex) return false;
    setState(() => _selectedIndex = next);
    return true;
  }

  void trigger() {
    if (_isDownloading) return;
    SfxService().playEnterSound();
    if (!_manualExists) {
      _downloadManual();
      return;
    }
    switch (_selectedIndex) {
      case 0:
        _readManual();
        return;
      case 1:
        _downloadManual(forceOverwrite: true);
        return;
      case 2:
        _deleteManual();
        return;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = _manualPath;
    int? size;
    if (_manualExists && path != null) {
      try {
        size = File(path).lengthSync();
      } catch (_) {
        size = null;
      }
    }

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16.r, 12.r, 16.r, 8.r),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Container(
              padding: EdgeInsets.all(14.r),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.16,
                ),
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.15),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Symbols.menu_book_rounded,
                    size: 62.r,
                    color: _manualExists
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface.withValues(alpha: 0.32),
                  ),
                  SizedBox(height: 10.r),
                  Text(
                    _manualExists
                        ? AppLocale.manualReady.getString(context)
                        : AppLocale.manualNotDownloaded.getString(context),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.r,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  SizedBox(height: 4.r),
                  Text(
                    _manualExists && size != null
                        ? 'PDF • ${_formatFileSize(size)}'
                        : AppLocale.manualDownloadHint.getString(context),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 8.5.r,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.58),
                    ),
                  ),
                  if (_isDownloading) ...[
                    SizedBox(height: 14.r),
                    LinearProgressIndicator(value: _downloadProgress),
                    SizedBox(height: 5.r),
                    Text(
                      AppLocale.downloadingManual.getString(context),
                      style: TextStyle(
                        fontSize: 8.r,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(width: 12.r),
          Expanded(
            flex: 6,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: _manualExists
                  ? [
                      _actionTile(
                        context,
                        index: 0,
                        icon: Symbols.menu_book_rounded,
                        title: AppLocale.readManual.getString(context),
                        subtitle: AppLocale.readManualDesc.getString(context),
                        onTap: () => _readManual(),
                      ),
                      SizedBox(height: 8.r),
                      _actionTile(
                        context,
                        index: 1,
                        icon: Symbols.download_rounded,
                        title: AppLocale.redownloadManual.getString(context),
                        subtitle: AppLocale.redownloadManualDesc.getString(context),
                        onTap: () => _downloadManual(forceOverwrite: true),
                      ),
                      SizedBox(height: 8.r),
                      _actionTile(
                        context,
                        index: 2,
                        icon: Symbols.delete_rounded,
                        title: AppLocale.deleteManual.getString(context),
                        subtitle: AppLocale.deleteManualDesc.getString(context),
                        onTap: () => _deleteManual(),
                        destructive: true,
                      ),
                    ]
                  : [
                      _actionTile(
                        context,
                        index: 0,
                        icon: Symbols.download_rounded,
                        title: AppLocale.downloadManual.getString(context),
                        subtitle: AppLocale.downloadManualDesc.getString(context),
                        onTap: () => _downloadManual(),
                      ),
                    ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile(
    BuildContext context, {
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final theme = Theme.of(context);
    final selected = _selectedIndex == index;
    final accent = destructive
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isDownloading ? null : onTap,
        borderRadius: BorderRadius.circular(10.r),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: EdgeInsets.symmetric(horizontal: 12.r, vertical: 10.r),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.15)
                : theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.10,
                  ),
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(
              color: selected ? accent : Colors.transparent,
              width: 1.5.r,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 22.r, color: accent),
              SizedBox(width: 10.r),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 10.r,
                        fontWeight: FontWeight.w600,
                        color: selected ? accent : theme.colorScheme.onSurface,
                      ),
                    ),
                    SizedBox(height: 2.r),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 7.8.r,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
