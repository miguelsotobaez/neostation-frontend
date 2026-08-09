import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/repositories/config_repository.dart';
import 'package:neostation/repositories/system_repository.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/services/global_notification_service.dart';
import 'package:neostation/services/metadata_cleanup_service.dart';
import 'package:neostation/services/rom_folder_organizer_service.dart';
import 'package:neostation/widgets/confirm_action_dialog.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/widgets/info_dialog.dart';
import 'settings_title.dart';
import 'widgets/settings_card_row.dart';
import 'widgets/settings_action_button.dart';

class ToolsSettingsContent extends StatefulWidget {
  final bool isContentFocused;
  final int selectedContentIndex;

  const ToolsSettingsContent({
    super.key,
    required this.isContentFocused,
    required this.selectedContentIndex,
  });

  @override
  State<ToolsSettingsContent> createState() => ToolsSettingsContentState();
}

class ToolsSettingsContentState extends State<ToolsSettingsContent> {
  static final _log = LoggerService.instance;
  bool _isOrganizingMultiDisc = false;
  bool _isCleaningMetadata = false;
  List<String> _currentRomFolders = [];

  @override
  void initState() {
    super.initState();
    _loadRomFolders();
  }

  Future<void> _loadRomFolders() async {
    try {
      _currentRomFolders = await ConfigRepository.getUserRomFolders();
      if (mounted) setState(() {});
    } catch (e) {
      _log.e('Failed to load ROM folders for tools: $e');
    }
  }

  int getItemCount() => 2;

  void scrollToIndex(int index) {}

  void selectItem(int index) {
    switch (index) {
      case 0:
        _organizeMultiDiscGames();
      case 1:
        _cleanOrphanedMetadata();
    }
  }

  Future<void> _organizeMultiDiscGames() async {
    if (_isOrganizingMultiDisc) return;

    final localeTitle = AppLocale.organizeMultiDiscGames.getString(context);
    final localeWarning = AppLocale.organizeMultiDiscWarning.getString(context);
    final localeNoFolders = AppLocale.organizeMultiDiscNoRomFoldersConfigured
        .getString(context);
    final localeScanning = AppLocale.organizeMultiDiscScanning.getString(
      context,
    );
    final localeDone = AppLocale.organizeMultiDiscDone.getString(context);
    final localeNoSetsFound = AppLocale.organizeMultiDiscNoSetsFound.getString(
      context,
    );
    final localeSkippedSuffix = AppLocale.organizeMultiDiscSkippedSuffix
        .getString(context);
    final localeFailed = AppLocale.organizeMultiDiscFailed.getString(context);
    final localeConfirm = AppLocale.confirm.getString(context);

    if (_currentRomFolders.isEmpty) {
      if (mounted) {
        AppNotification.showNotification(
          context,
          localeNoFolders,
          type: NotificationType.info,
        );
      }
      return;
    }

    final confirmed = await ConfirmActionDialog.show(
      context,
      title: localeTitle,
      body: localeWarning,
      confirmLabel: localeConfirm,
      icon: Symbols.folder_managed_rounded,
      accentColor: Theme.of(context).colorScheme.primary,
    );
    if (confirmed != true || !mounted) return;

    final multiDiscSystems = (await SystemRepository.getAllSystems())
        .where((system) => system.multiDisc)
        .toList();
    final supportedFolders = multiDiscSystems
        .expand((system) => [system.folderName, ...system.folders])
        .where((folder) => folder.isNotEmpty)
        .toSet();

    String? completionMessage;
    NotificationType? completionType;
    const notificationId = 'organize_multidisc';

    try {
      if (mounted) setState(() => _isOrganizingMultiDisc = true);

      GlobalNotificationService().show(
        id: notificationId,
        message: localeScanning,
        type: GlobalNotificationType.info,
        progress: 0,
      );

      final result = await RomFolderOrganizerService.organizeRomFolders(
        _currentRomFolders,
        supportedSystemFolders: supportedFolders,
        onProgress: (completed, total) {
          if (total == 0) return;
          GlobalNotificationService().update(
            id: notificationId,
            message: localeScanning,
            type: GlobalNotificationType.info,
            progress: completed / total,
          );
        },
      );

      if (result.hasChanges && mounted) {
        final configProvider = Provider.of<SqliteConfigProvider>(
          context,
          listen: false,
        );
        for (final system in multiDiscSystems) {
          await configProvider.rescanSystemSilent(system);
        }
      }

      if (mounted) {
        final skippedNote = result.rootsSkipped > 0
            ? localeSkippedSuffix.replaceFirst(
                '{count}',
                result.rootsSkipped.toString(),
              )
            : '';
        completionMessage = result.hasChanges
            ? localeDone
                  .replaceFirst('{groups}', result.groupsOrganized.toString())
                  .replaceFirst('{files}', result.filesMoved.toString())
                  .replaceFirst(
                    '{playlists}',
                    result.playlistsCreated.toString(),
                  )
                  .replaceFirst('{skipped}', skippedNote)
            : localeNoSetsFound.replaceFirst('{skipped}', skippedNote);
        completionType = result.hasChanges
            ? NotificationType.success
            : NotificationType.info;
      }
    } catch (e, stackTrace) {
      _log.e('Failed to organize multi-disc games: $e', stackTrace: stackTrace);
      if (mounted) {
        completionMessage = localeFailed.replaceFirst('{error}', e.toString());
        completionType = NotificationType.error;
      }
    } finally {
      if (mounted) {
        setState(() => _isOrganizingMultiDisc = false);
        await _loadRomFolders();
        if (completionMessage != null && completionType != null) {
          final globalType = completionType == NotificationType.success
              ? GlobalNotificationType.success
              : GlobalNotificationType.error;
          GlobalNotificationService().update(
            id: notificationId,
            message: completionMessage,
            type: globalType,
            progress: null,
          );
        }
      } else {
        GlobalNotificationService().dismiss(notificationId);
      }
    }
  }

  Future<void> _cleanOrphanedMetadata() async {
    if (_isCleaningMetadata) return;

    final locale = AppLocale.cleanOrphanedMetadata.getString(context);
    final localeWarning = AppLocale.cleanOrphanedMetadataWarning.getString(
      context,
    );
    final localeNothingFound = AppLocale.cleanOrphanedMetadataNothingFound
        .getString(context);
    final localeScanning = AppLocale.cleanOrphanedMetadataScanning.getString(
      context,
    );
    final localeCleaningItem = AppLocale.cleanOrphanedMetadataCleaningItem
        .getString(context);
    final localeDelete = AppLocale.delete.getString(context);
    final localeFailed = AppLocale.cleanOrphanedMetadataFailed.getString(
      context,
    );
    final localeDone = AppLocale.cleanOrphanedMetadataDone.getString(context);
    final localeEsdeSkipped = AppLocale.cleanOrphanedMetadataEsdeSkippedSuffix
        .getString(context);

    final fileProvider = Provider.of<FileProvider>(context, listen: false);
    if (!fileProvider.isInitialized) {
      if (mounted) {
        AppNotification.showNotification(
          context,
          localeFailed.replaceFirst('{error}', 'File provider not initialized'),
          type: NotificationType.error,
        );
      }
      return;
    }

    // Analyze without deleting so the user can review what will be affected.
    final analysis = await MetadataCleanupService.analyze();
    if (!mounted) return;

    if (!analysis.hasOrphans) {
      await InfoDialog.show(
        context,
        title: locale,
        body: localeNothingFound,
        okLabel: AppLocale.ok.getString(context),
        icon: Symbols.cleaning_services_rounded,
      );
      return;
    }

    final neoStationCount = analysis.orphanedItems
        .where((i) => i.isNeoStation)
        .length;
    final esdeCount = analysis.orphanedItems
        .where((i) => i.esdeImported)
        .length;

    final body = StringBuffer()
      ..writeln(localeWarning)
      ..writeln()
      ..writeln(
        'Found ${analysis.orphanedItems.length} orphaned metadata entr${analysis.orphanedItems.length == 1 ? 'y' : 'ies'}. '
        '$neoStationCount will be deleted from the database and disk.',
      );
    if (esdeCount > 0) {
      body.writeln(
        '$esdeCount ES-DE imported entr${esdeCount == 1 ? 'y' : 'ies'} will be left untouched.',
      );
    }

    final accentColor = Theme.of(context).colorScheme.error;
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: locale,
      body: body.toString().trim(),
      confirmLabel: localeDelete,
      icon: Symbols.cleaning_services_rounded,
      accentColor: accentColor,
    );
    if (confirmed != true || !mounted) return;

    String? completionMessage;
    NotificationType? completionType;
    const notificationId = 'clean_orphaned_metadata';

    try {
      if (mounted) setState(() => _isCleaningMetadata = true);

      // Use the global notification service so the progress bar survives tab
      // and menu navigation while the cleanup runs.
      GlobalNotificationService().show(
        id: notificationId,
        message: localeScanning,
        type: GlobalNotificationType.info,
        progress: 0,
      );

      final result = await MetadataCleanupService.clean(
        fileProvider: fileProvider,
        onProgress: (progress, currentItem) {
          GlobalNotificationService().update(
            id: notificationId,
            message: localeCleaningItem.replaceFirst(
              '{filename}',
              currentItem.filename,
            ),
            type: GlobalNotificationType.info,
            progress: progress,
          );
        },
      );

      if (mounted) {
        final esdeSkippedNote = result.skippedEsdeItems.isNotEmpty
            ? localeEsdeSkipped.replaceFirst(
                '{count}',
                result.skippedEsdeItems.length.toString(),
              )
            : '';
        if (result.hasDeletions) {
          completionMessage =
              localeDone
                  .replaceFirst(
                    '{entries}',
                    result.deletedItems.length.toString(),
                  )
                  .replaceFirst(
                    '{files}',
                    result.deletedMediaFiles.toString(),
                  ) +
              esdeSkippedNote;
          completionType = NotificationType.success;
        } else {
          completionMessage = localeNothingFound + esdeSkippedNote;
          completionType = NotificationType.info;
        }
      }
    } catch (e, stackTrace) {
      _log.e('Failed to clean orphaned metadata: $e', stackTrace: stackTrace);
      if (mounted) {
        completionMessage = localeFailed.replaceFirst('{error}', e.toString());
        completionType = NotificationType.error;
      }
    } finally {
      if (mounted) {
        setState(() => _isCleaningMetadata = false);
        if (completionMessage != null && completionType != null) {
          final globalType = completionType == NotificationType.success
              ? GlobalNotificationType.success
              : GlobalNotificationType.error;
          GlobalNotificationService().update(
            id: notificationId,
            message: completionMessage,
            type: globalType,
            progress: null,
          );
        }
      } else {
        // Make sure the persistent notification is removed if the widget that
        // started the operation is no longer in the tree.
        GlobalNotificationService().dismiss(notificationId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSelected =
        widget.isContentFocused && widget.selectedContentIndex == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsTitle(
          title: AppLocale.tools.getString(context),
          subtitle: AppLocale.toolsSubtitle.getString(context),
        ),
        SizedBox(height: 12.r),
        Expanded(
          child: ValueListenableBuilder<List<GlobalNotificationData>>(
            valueListenable: GlobalNotificationService().notifier,
            builder: (context, notifications, _) {
              final multiDiscProgress = _progressFor(
                notifications,
                'organize_multidisc',
              );
              final metadataProgress = _progressFor(
                notifications,
                'clean_orphaned_metadata',
              );

              return ListView(
                physics: const ClampingScrollPhysics(),
                children: [
                  SettingsCardRow(
                    icon: Symbols.folder_managed_rounded,
                    title: AppLocale.organizeMultiDiscGames.getString(context),
                    subtitle: AppLocale.organizeMultiDiscGamesSubtitle
                        .getString(context),
                    subtitleMaxLines: 2,
                    selected: isSelected,
                    onTap: () => _organizeMultiDiscGames(),
                    trailing: SettingsActionButton(
                      icon: Symbols.folder_managed_rounded,
                      selected: isSelected,
                    ),
                    belowContent: _buildInlineProgress(
                      context,
                      multiDiscProgress,
                    ),
                  ),
                  SettingsCardRow(
                    icon: Symbols.cleaning_services_rounded,
                    title: AppLocale.cleanOrphanedMetadata.getString(context),
                    subtitle: AppLocale.cleanOrphanedMetadataSubtitle.getString(
                      context,
                    ),
                    subtitleMaxLines: 2,
                    selected:
                        widget.isContentFocused &&
                        widget.selectedContentIndex == 1,
                    onTap: () => _cleanOrphanedMetadata(),
                    trailing: SettingsActionButton(
                      icon: Symbols.cleaning_services_rounded,
                      selected:
                          widget.isContentFocused &&
                          widget.selectedContentIndex == 1,
                    ),
                    belowContent: _buildInlineProgress(
                      context,
                      metadataProgress,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static GlobalNotificationData? _progressFor(
    List<GlobalNotificationData> notifications,
    String id,
  ) {
    for (final notification in notifications) {
      if (notification.id == id) return notification;
    }
    return null;
  }

  /// Inline progress shown inside the card row while a long-running tool runs,
  /// mirroring the notification the header bell keeps for the same operation.
  Widget _buildInlineProgress(
    BuildContext context,
    GlobalNotificationData? notification,
  ) {
    if (notification == null || notification.progress == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final progress = notification.progress!;

    return Padding(
      padding: EdgeInsets.only(top: 8.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2.r),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 4.r,
                    backgroundColor: theme.colorScheme.surface.withValues(
                      alpha: 0.4,
                    ),
                    valueColor: AlwaysStoppedAnimation<Color>(
                      theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 8.r),
              Text(
                '${(progress * 100).round()}%',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 10.r,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (notification.message.isNotEmpty) ...[
            SizedBox(height: 4.r),
            Text(
              notification.message,
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                fontSize: 9.r,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}
