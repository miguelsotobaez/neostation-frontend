import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/repositories/config_repository.dart';
import 'package:neostation/repositories/system_repository.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/services/rom_folder_organizer_service.dart';
import 'package:neostation/widgets/custom_notification.dart';
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

  int getItemCount() => 1;

  void scrollToIndex(int index) {}

  void selectItem(int index) {
    if (index == 0) _organizeMultiDiscGames();
  }

  Future<void> _organizeMultiDiscGames() async {
    if (_isOrganizingMultiDisc) return;

    if (_currentRomFolders.isEmpty) {
      if (mounted) {
        AppNotification.showNotification(
          context,
          AppLocale.organizeMultiDiscNoRomFoldersConfigured.getString(context),
          type: NotificationType.info,
        );
      }
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocale.organizeMultiDiscGames.getString(context)),
        content: Text(AppLocale.organizeMultiDiscWarning.getString(context)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppLocale.cancel.getString(context)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppLocale.confirm.getString(context)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final multiDiscSystems = (await SystemRepository.getAllSystems())
        .where((system) => system.multiDisc)
        .toList();
    final supportedFolders = multiDiscSystems
        .expand((system) => [system.folderName, ...system.folders])
        .where((folder) => folder.isNotEmpty)
        .toSet();

    setState(() => _isOrganizingMultiDisc = true);
    if (mounted) {
      AppNotification.showNotification(
        context,
        AppLocale.organizeMultiDiscScanning.getString(context),
        type: NotificationType.info,
        duration: const Duration(minutes: 5),
        notificationId: 'organize_multidisc',
        progress: 0,
      );
    }

    String? completionMessage;
    NotificationType? completionType;
    try {
      final result = await RomFolderOrganizerService.organizeRomFolders(
        _currentRomFolders,
        supportedSystemFolders: supportedFolders,
        onProgress: (completed, total) {
          if (!mounted || total == 0) return;
          AppNotification.showNotification(
            context,
            AppLocale.organizeMultiDiscScanning.getString(context),
            type: NotificationType.info,
            notificationId: 'organize_multidisc',
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
            ? AppLocale.organizeMultiDiscSkippedSuffix
                  .getString(context)
                  .replaceFirst('{count}', result.rootsSkipped.toString())
            : '';
        completionMessage = result.hasChanges
            ? AppLocale.organizeMultiDiscDone
                  .getString(context)
                  .replaceFirst('{groups}', result.groupsOrganized.toString())
                  .replaceFirst('{files}', result.filesMoved.toString())
                  .replaceFirst(
                    '{playlists}',
                    result.playlistsCreated.toString(),
                  )
                  .replaceFirst('{skipped}', skippedNote)
            : AppLocale.organizeMultiDiscNoSetsFound
                  .getString(context)
                  .replaceFirst('{skipped}', skippedNote);
        completionType = result.hasChanges
            ? NotificationType.success
            : NotificationType.info;
      }
    } catch (e) {
      _log.e('Failed to organize multi-disc games: $e');
      if (mounted) {
        completionMessage = AppLocale.organizeMultiDiscFailed
            .getString(context)
            .replaceFirst('{error}', e.toString());
        completionType = NotificationType.error;
      }
    } finally {
      if (mounted) {
        setState(() => _isOrganizingMultiDisc = false);
        await _loadRomFolders();
        if (completionMessage != null && completionType != null && mounted) {
          AppNotification.showNotification(
            context,
            completionMessage,
            type: completionType,
            duration: const Duration(seconds: 10),
          );
        }
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
          child: ListView(
            physics: const ClampingScrollPhysics(),
            children: [
              SettingsCardRow(
                icon: Symbols.folder_managed_rounded,
                title: AppLocale.organizeMultiDiscGames.getString(context),
                subtitle: AppLocale.organizeMultiDiscGamesSubtitle.getString(
                  context,
                ),
                subtitleMaxLines: 2,
                selected: isSelected,
                onTap: () => _organizeMultiDiscGames(),
                trailing: SettingsActionButton(
                  icon: Symbols.folder_managed_rounded,
                  selected: isSelected,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
