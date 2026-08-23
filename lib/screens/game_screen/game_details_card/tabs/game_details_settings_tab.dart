import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/widgets/confirm_action_dialog.dart';
import 'package:neostation/widgets/delete_game_dialog.dart';
import 'package:neostation/widgets/settings_rows.dart';
import 'package:provider/provider.dart';
import '../../../../models/system_model.dart';
import '../../../../providers/file_provider.dart';
import '../../../../models/game_model.dart';
import '../../../../models/core_emulator_model.dart';
import '../../../../sync/i_sync_provider.dart';
import '../../../../providers/neo_sync_provider.dart';
import '../../../../providers/romm_provider.dart';
import '../../../../repositories/game_repository.dart';
import '../../../../utils/emulator_loader.dart';
import '../../../../utils/game_utils.dart';

/// A tab component that manages per-game configuration, including emulator overrides and synchronization.
///
/// Provides controls for cloud-save authorization, play-time persistence management, and
/// fine-grained emulator selection with cross-platform package verification.
class GameDetailsSettingsTab extends StatefulWidget {
  final SystemModel system;
  final GameModel game;
  final ISyncProvider syncProvider;
  final bool isAllMode;
  final VoidCallback? onGameUpdated;
  final void Function(String romname)? onGameDeleted;

  const GameDetailsSettingsTab({
    super.key,
    required this.system,
    required this.game,
    required this.syncProvider,
    required this.isAllMode,
    this.onGameUpdated,
    this.onGameDeleted,
  });

  @override
  State<GameDetailsSettingsTab> createState() => GameDetailsSettingsTabState();
}

class GameDetailsSettingsTabState extends State<GameDetailsSettingsTab> {
  static final _log = LoggerService.instance;

  late GameModel _game;
  late bool _cloudSyncEnabled;
  bool _isUpdatingCloudSync = false;
  bool _isResettingPlayTime = false;
  bool _isDeleting = false;
  List<CoreEmulatorModel> _availableEmulators = [];
  int _settingsSelectedIndex = 0;

  /// Tracks the active emulator override. Uses a sentinel to differentiate
  /// between 'not yet loaded' and 'explicit null' (system default).
  Object? _activeEmulatorId = _sentinel;
  static const Object _sentinel = Object();

  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _settingsItemKeys = {};

  GlobalKey _settingsKey(int navIndex) =>
      _settingsItemKeys.putIfAbsent(navIndex, () => GlobalKey());

  bool get _settingsShowCloudSync => widget.syncProvider.isAuthenticated;
  int get _settingsCloudSyncIdx => 0;
  int get _settingsPlayTimeIdx => _settingsShowCloudSync ? 1 : 0;
  int get _settingsDeleteGameIdx => _settingsPlayTimeIdx + 1;
  bool get _settingsShowEmulators => _availableEmulators.length > 1;
  int get _settingsEmulatorStartIdx => _settingsDeleteGameIdx + 1;
  int get _settingsEmulatorItemCount =>
      _settingsShowEmulators ? 1 + _availableEmulators.length : 0;
  int get _settingsTotalItems =>
      _settingsDeleteGameIdx + 1 + _settingsEmulatorItemCount;

  /// Resolves the current emulator ID, falling back to the game's persistence value if uninitialized.
  String? get _resolvedEmulatorId => identical(_activeEmulatorId, _sentinel)
      ? _game.emulatorName
      : _activeEmulatorId as String?;

  @override
  void initState() {
    super.initState();
    _game = widget.game;
    _cloudSyncEnabled = widget.game.cloudSyncEnabled ?? true;
    _activeEmulatorId = _sentinel;
    _loadEmulators();
  }

  @override
  void didUpdateWidget(covariant GameDetailsSettingsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.game.romname != oldWidget.game.romname ||
        widget.game.systemFolderName != oldWidget.game.systemFolderName) {
      _game = widget.game;
      _cloudSyncEnabled = widget.game.cloudSyncEnabled ?? true;
      _activeEmulatorId = _sentinel;
      _settingsSelectedIndex = 0;
      _loadEmulators();
    }
  }

  /// Gamepad navigation delegate: Decrement focused item index.
  void moveUp() {
    setState(() {
      _settingsSelectedIndex = (_settingsSelectedIndex - 1).clamp(
        0,
        _settingsTotalItems - 1,
      );
    });
    _scrollToSelectedSettingsItem();
  }

  /// Gamepad navigation delegate: Increment focused item index.
  void moveDown() {
    setState(() {
      _settingsSelectedIndex = (_settingsSelectedIndex + 1).clamp(
        0,
        _settingsTotalItems - 1,
      );
    });
    _scrollToSelectedSettingsItem();
  }

  /// Action trigger delegate: Executes the operation associated with the focused row.
  void trigger() => _handleSettingsTrigger();

  /// Synchronizes the scroll viewport with the currently focused settings item.
  void _scrollToSelectedSettingsItem() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _settingsItemKeys[_settingsSelectedIndex];
      if (key?.currentContext != null) {
        Scrollable.ensureVisible(
          key!.currentContext!,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          alignment: 0.5,
        );
      }
    });
  }

  /// Main input arbiter for settings interactions.
  void _handleSettingsTrigger() {
    final idx = _settingsSelectedIndex;

    // Cloud Sync Toggle.
    if (_settingsShowCloudSync && idx == _settingsCloudSyncIdx) {
      if (!_isUpdatingCloudSync) _toggleCloudSync(!_cloudSyncEnabled);
    }
    // Play-time Reset Action.
    else if (idx == _settingsPlayTimeIdx) {
      if ((_game.playTime ?? 0) > 0) _confirmResetPlayTime();
    }
    // Delete Game Action.
    else if (idx == _settingsDeleteGameIdx) {
      _confirmDeleteGame();
    }
    // Emulator Selection.
    else if (_settingsShowEmulators && idx >= _settingsEmulatorStartIdx) {
      final emuIdx = idx - _settingsEmulatorStartIdx;
      if (emuIdx == 0) {
        _setEmulatorOverride(null); // Revert to system default.
      } else {
        final emulator = _availableEmulators[emuIdx - 1];
        if (!emulator.isInstalled) return;
        _setEmulatorOverride(emulator);
      }
    }
  }

  /// Hydrates the list of supported emulators via the shared loader.
  Future<void> _loadEmulators() async {
    final emulators = await loadEmulatorsForSystem(widget.system);
    if (mounted) {
      setState(() {
        _availableEmulators = emulators;
      });
    }
  }

  /// Clears the recorded play-time for the specific ROM in the local database.
  Future<void> _resetPlayTime() async {
    if (_isResettingPlayTime) return;
    setState(() => _isResettingPlayTime = true);
    try {
      final targetSystemFolder =
          widget.isAllMode && _game.systemFolderName != null
          ? _game.systemFolderName!
          : widget.system.folderName;
      await GameRepository.resetPlayTime(targetSystemFolder, _game.romname);
      setState(() {
        _game = _game.copyWith(playTime: 0);
      });
      widget.onGameUpdated?.call();
      if (mounted) {
        AppNotification.showNotification(
          context,
          'Play time reset',
          type: NotificationType.success,
        );
      }
    } catch (e) {
      _log.e('Play-time reset operation failed: \$e');
    } finally {
      if (mounted) setState(() => _isResettingPlayTime = false);
    }
  }

  /// Confirms with the user before clearing the recorded play-time.
  Future<void> _confirmResetPlayTime() async {
    SfxService().playNavSound();
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: AppLocale.resetPlayTimeConfirm.getString(context),
      body: AppLocale.resetPlayTimeConfirmBody.getString(context),
      confirmLabel: AppLocale.reset.getString(context),
      icon: Symbols.timer_off_rounded,
    );
    if (confirmed && mounted) {
      _resetPlayTime();
    }
  }

  /// Shows a confirmation dialog and permanently deletes the game and its data.
  Future<void> _confirmDeleteGame() async {
    SfxService().playNavSound();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          DeleteGameDialog(gameName: _game.name, romName: _game.romname),
    );
    if (confirmed == true && mounted) {
      _deleteGame();
    }
  }

  /// Permanently deletes the current game from the database, its scraped media,
  /// and the ROM file on disk, then navigates back.
  Future<void> _deleteGame() async {
    if (_isDeleting) return;
    setState(() => _isDeleting = true);

    final targetSystemFolder =
        widget.isAllMode && _game.systemFolderName != null
        ? _game.systemFolderName!
        : widget.system.folderName;
    final targetSystemId = _game.systemId ?? widget.system.id;
    final fileProvider = Provider.of<FileProvider>(context, listen: false);
    // Read before the await: the card can be gone by the time deletion ends.
    final rommProvider = Provider.of<RommProvider>(context, listen: false);
    final deletedRomname = _game.romname;

    try {
      await GameRepository.deleteGame(
        appSystemId: targetSystemId,
        filename: deletedRomname,
        systemFolderName: targetSystemFolder,
        romBaseName: deletedRomname,
        romPath: _game.romPath,
        fileProvider: fileProvider,
      );
      // Unlink from RomM so the browse grid stops calling it downloaded.
      await rommProvider.forgetLocalDownload(
        romname: deletedRomname,
        systemFolder: targetSystemFolder,
      );
    } catch (e) {
      _log.e('Game deletion failed: $e');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }

    if (mounted) {
      widget.onGameDeleted?.call(deletedRomname);
    }
  }

  /// Persists a manual emulator override for this specific game.
  Future<void> _setEmulatorOverride(CoreEmulatorModel? emulator) async {
    // Optimistic Update: Reflect changes in UI immediately.
    if (mounted) setState(() => _activeEmulatorId = emulator?.uniqueId);
    try {
      final targetSystemFolder =
          widget.isAllMode && _game.systemFolderName != null
          ? _game.systemFolderName!
          : widget.system.folderName;
      await GameRepository.setEmulatorOverride(
        targetSystemFolder,
        _game.romname,
        emulator?.uniqueId,
        emulator?.osId,
      );
      widget.onGameUpdated?.call();
    } catch (e) {
      _log.e('Emulator override persistence failed: \$e');
      // Rollback: Revert UI state on failure.
      if (mounted) setState(() => _activeEmulatorId = _game.emulatorName);
    }
  }

  /// Updates the cloud synchronization authorization for the current ROM.
  Future<void> _toggleCloudSync(bool value) async {
    if (_isUpdatingCloudSync) return;
    setState(() => _isUpdatingCloudSync = true);
    try {
      final targetSystemFolder =
          widget.isAllMode && widget.game.systemFolderName != null
          ? widget.game.systemFolderName!
          : widget.system.folderName;

      await GameRepository.updateCloudSyncEnabled(
        targetSystemFolder,
        widget.game.romname,
        value,
      );

      await widget.syncProvider.updateGameCloudSyncEnabled(
        widget.game.romname,
        value,
      );

      setState(() => _cloudSyncEnabled = value);

      if (value) {
        final updatedGame = widget.game.copyWith(cloudSyncEnabled: true);
        if (mounted) {
          if (widget.syncProvider is NeoSyncProvider) {
            await (widget.syncProvider as NeoSyncProvider).updateSelectedGame(
              widget.game.romname,
              (romname) async => updatedGame,
            );
          }
          if (mounted) {
            // Trigger an immediate sync-down to ensure the ROM is ready for play.
            await widget.syncProvider.syncGameSavesBeforeLaunch(updatedGame);
          }
        }
      }
    } catch (e) {
      _log.e('Cloud-sync status update failed: \$e');
    } finally {
      if (mounted) setState(() => _isUpdatingCloudSync = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12.r,
      right: 12.r,
      top: 55.r,
      bottom: 98.r,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8.r),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 2.r,
              offset: Offset(2.0.r, 2.0.r),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Category title and icon.
            Padding(
              padding: EdgeInsets.fromLTRB(8.r, 8.r, 8.r, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Symbols.settings_rounded,
                        color: Theme.of(context).colorScheme.onSurface,
                        size: 13.r,
                      ),
                      SizedBox(width: 6.r),
                      Text(
                        AppLocale.gameSettings.getString(context),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 12.r,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  Divider(
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.3),
                    height: 10.r,
                  ),
                ],
              ),
            ),

            // Content: Scrollable list of actionable settings.
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.r),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Cloud Synchronization Option.
                      if (_settingsShowCloudSync)
                        SettingsRow(
                          key: _settingsKey(_settingsCloudSyncIdx),
                          isSelected:
                              _settingsSelectedIndex == _settingsCloudSyncIdx,
                          icon: Symbols.cloud_rounded,
                          label: AppLocale.cloudSync.getString(context),
                          subtitle: _cloudSyncEnabled
                              ? AppLocale.cloudSyncOn.getString(context)
                              : AppLocale.cloudSyncOff.getString(context),
                          onTap: () {
                            SfxService().playNavSound();
                            setState(
                              () => _settingsSelectedIndex =
                                  _settingsCloudSyncIdx,
                            );
                            if (!_isUpdatingCloudSync) {
                              _toggleCloudSync(!_cloudSyncEnabled);
                            }
                          },
                          trailing: _isUpdatingCloudSync
                              ? SizedBox(
                                  width: 20.r,
                                  height: 20.r,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                  ),
                                )
                              : ExcludeFocus(
                                  child: Switch(
                                    value: _cloudSyncEnabled,
                                    onChanged: !_isUpdatingCloudSync
                                        ? (v) => _toggleCloudSync(v)
                                        : null,
                                    activeThumbColor: Colors.lightGreen,
                                  ),
                                ),
                        ),
                      SizedBox(height: 4.r),

                      // Play-time Statistics & Reset Option.
                      SettingsRow(
                        key: _settingsKey(_settingsPlayTimeIdx),
                        isSelected:
                            _settingsSelectedIndex == _settingsPlayTimeIdx,
                        icon: Symbols.timer_off_rounded,
                        label: AppLocale.playTime.getString(context),
                        subtitle: GameUtils.formatPlayTime(_game.playTime ?? 0),
                        onTap: () {
                          SfxService().playNavSound();
                          setState(
                            () => _settingsSelectedIndex = _settingsPlayTimeIdx,
                          );
                          if ((_game.playTime ?? 0) > 0 &&
                              !_isResettingPlayTime) {
                            _confirmResetPlayTime();
                          }
                        },
                        trailing: _isResettingPlayTime
                            ? SizedBox(
                                width: 20.r,
                                height: 20.r,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                ),
                              )
                            : ExcludeFocus(
                                child: Builder(
                                  builder: (context) {
                                    final canReset =
                                        (_game.playTime ?? 0) > 0 &&
                                        !_isResettingPlayTime;
                                    final theme = Theme.of(context);
                                    return GestureDetector(
                                      onTap: canReset
                                          ? _confirmResetPlayTime
                                          : null,
                                      child: Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 8.r,
                                          vertical: 3.r,
                                        ),
                                        decoration: BoxDecoration(
                                          color: canReset
                                              ? theme.colorScheme.error
                                                    .withValues(alpha: 0.15)
                                              : theme.colorScheme.onSurface
                                                    .withValues(alpha: 0.05),
                                          borderRadius: BorderRadius.circular(
                                            4.r,
                                          ),
                                          border: Border.all(
                                            color: canReset
                                                ? theme.colorScheme.error
                                                      .withValues(alpha: 0.4)
                                                : theme.colorScheme.onSurface
                                                      .withValues(alpha: 0.1),
                                            width: 1.r,
                                          ),
                                        ),
                                        child: Text(
                                          AppLocale.reset.getString(context),
                                          style: TextStyle(
                                            fontSize: 11.r,
                                            fontWeight: FontWeight.w600,
                                            color: canReset
                                                ? theme.colorScheme.error
                                                : theme.colorScheme.onSurface
                                                      .withValues(alpha: 0.3),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),

                      // Delete Game Option.
                      SettingsRow(
                        key: _settingsKey(_settingsDeleteGameIdx),
                        isSelected:
                            _settingsSelectedIndex == _settingsDeleteGameIdx,
                        icon: Symbols.delete_rounded,
                        label: AppLocale.deleteGame.getString(context),
                        subtitle: AppLocale.deleteGameSubtitle.getString(
                          context,
                        ),
                        onTap: () {
                          SfxService().playNavSound();
                          setState(
                            () =>
                                _settingsSelectedIndex = _settingsDeleteGameIdx,
                          );
                          _confirmDeleteGame();
                        },
                        trailing: _isDeleting
                            ? SizedBox(
                                width: 20.r,
                                height: 20.r,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              )
                            : ExcludeFocus(
                                child: Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8.r,
                                    vertical: 3.r,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.error.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4.r),
                                    border: Border.all(
                                      color: Theme.of(context).colorScheme.error
                                          .withValues(alpha: 0.4),
                                      width: 1.r,
                                    ),
                                  ),
                                  child: Text(
                                    AppLocale.delete.getString(context),
                                    style: TextStyle(
                                      fontSize: 11.r,
                                      fontWeight: FontWeight.w600,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.error,
                                    ),
                                  ),
                                ),
                              ),
                      ),
                      SizedBox(height: 8.r),

                      // Emulator Overrides Section.
                      if (_settingsShowEmulators) ...[
                        SizedBox(height: 8.r),
                        Padding(
                          padding: EdgeInsets.only(left: 4.r, bottom: 4.r),
                          child: Row(
                            children: [
                              Icon(
                                Symbols.sports_esports_rounded,
                                size: 12.r,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.6),
                              ),
                              SizedBox(width: 4.r),
                              Text(
                                AppLocale.emulator.getString(context),
                                style: TextStyle(
                                  fontSize: 11.r,
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Global System Default Option.
                        EmulatorRow(
                          key: _settingsKey(_settingsEmulatorStartIdx),
                          isSelected:
                              _settingsSelectedIndex ==
                              _settingsEmulatorStartIdx,
                          label: AppLocale.systemDefault.getString(context),
                          isActive:
                              _resolvedEmulatorId == null ||
                              !_availableEmulators.any(
                                (e) => e.uniqueId == _resolvedEmulatorId,
                              ),
                          onTap: () {
                            SfxService().playNavSound();
                            setState(
                              () => _settingsSelectedIndex =
                                  _settingsEmulatorStartIdx,
                            );
                            _setEmulatorOverride(null);
                          },
                        ),
                        // Individual Emulator Options.
                        ..._availableEmulators.asMap().entries.map((entry) {
                          final i = entry.key;
                          final e = entry.value;
                          return EmulatorRow(
                            key: _settingsKey(
                              _settingsEmulatorStartIdx + 1 + i,
                            ),
                            isSelected:
                                _settingsSelectedIndex ==
                                _settingsEmulatorStartIdx + 1 + i,
                            label: e.name,
                            isActive: _resolvedEmulatorId == e.uniqueId,
                            onTap: () {
                              SfxService().playNavSound();
                              setState(
                                () => _settingsSelectedIndex =
                                    _settingsEmulatorStartIdx + 1 + i,
                              );
                              _setEmulatorOverride(e);
                            },
                            emulator: e,
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(height: 8.r),
          ],
        ),
      ),
    );
  }
}
