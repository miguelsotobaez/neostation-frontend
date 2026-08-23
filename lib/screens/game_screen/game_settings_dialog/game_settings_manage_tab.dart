import 'package:flutter/material.dart';
import 'package:flutter_localization/flutter_localization.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/neo_sync_provider.dart';
import 'package:neostation/providers/romm_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/providers/sqlite_database_provider.dart';
import 'package:neostation/repositories/game_repository.dart';
import 'package:neostation/repositories/system_repository.dart';
import 'package:neostation/utils/enabled_index_nav.dart';
import 'package:neostation/screens/settings_screen/new_settings_options/widgets/setting_row.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/services/sfx_service.dart';
import 'package:neostation/sync/i_sync_provider.dart';
import 'package:neostation/utils/game_utils.dart';
import 'package:neostation/widgets/confirm_action_dialog.dart';
import 'package:neostation/widgets/custom_notification.dart';
import 'package:neostation/widgets/custom_toggle_switch.dart';
import 'package:neostation/widgets/delete_game_dialog.dart';
import 'package:provider/provider.dart';

/// Manage tab for [GameSettingsDialog]: cloud sync, grid size/style,
/// play-time reset, hiding the game, and permanent game deletion. View mode is
/// selected from the game view itself (X button), not here.
class GameSettingsManageTab extends StatefulWidget {
  final GameModel game;
  final SystemModel system;
  final FileProvider fileProvider;
  final ISyncProvider? syncProvider;
  final bool isAllMode;
  final VoidCallback? onGameUpdated;
  final void Function(String romname)? onGameDeleted;
  final void Function(String romname)? onGameHidden;

  const GameSettingsManageTab({
    super.key,
    required this.game,
    required this.system,
    required this.fileProvider,
    this.syncProvider,
    required this.isAllMode,
    this.onGameUpdated,
    this.onGameDeleted,
    this.onGameHidden,
  });

  @override
  State<GameSettingsManageTab> createState() => GameSettingsManageTabState();
}

class GameSettingsManageTabState extends State<GameSettingsManageTab> {
  static final _log = LoggerService.instance;

  int _selectedIndex = 0;
  late bool _cloudSyncEnabled;
  bool _isUpdatingCloudSync = false;
  bool _isResettingPlayTime = false;
  bool _isHiding = false;
  bool _isDeleting = false;

  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};

  GlobalKey _itemKey(int navIndex) =>
      _itemKeys.putIfAbsent(navIndex, () => GlobalKey());

  // Navigation layout. Indices are fixed so focus doesn't jump around when
  // cloud sync visibility or the grid options change.
  int get _cloudSyncIdx => 0;
  int get _playTimeIdx => 1;
  int get _hideIdx => 2;
  int get _deleteIdx => 3;
  int get _totalItems => 4;

  bool get _showCloudSync => widget.syncProvider?.isAuthenticated == true;

  String get _targetSystemFolder =>
      widget.isAllMode && widget.game.systemFolderName != null
      ? widget.game.systemFolderName!
      : widget.system.folderName;

  @override
  void initState() {
    super.initState();
    _cloudSyncEnabled = widget.game.cloudSyncEnabled ?? true;
    _selectedIndex = _showCloudSync ? _cloudSyncIdx : _playTimeIdx;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// Returns whether [idx] can receive focus in the current state.
  bool _isEnabledIndex(int idx) {
    if (idx == _cloudSyncIdx && !_showCloudSync) return false;
    return idx >= 0 && idx < _totalItems;
  }

  // Clamp at the ends like the other tabs (no wrap); just skip disabled rows.
  int _previousEnabledIndex() =>
      previousEnabledIndex(_selectedIndex, _totalItems, _isEnabledIndex);

  int _nextEnabledIndex() =>
      nextEnabledIndex(_selectedIndex, _totalItems, _isEnabledIndex);

  void _ensureSelectedIndexEnabled() {
    if (!_isEnabledIndex(_selectedIndex)) {
      _selectedIndex = _nextEnabledIndex();
    }
  }

  void moveUp() {
    setState(() => _selectedIndex = _previousEnabledIndex());
    _scrollToSelectedItem();
  }

  void moveDown() {
    setState(() => _selectedIndex = _nextEnabledIndex());
    _scrollToSelectedItem();
  }

  void trigger() {
    final idx = _selectedIndex;
    if (_showCloudSync && idx == _cloudSyncIdx) {
      if (!_isUpdatingCloudSync) _toggleCloudSync(!_cloudSyncEnabled);
    } else if (idx == _playTimeIdx) {
      if ((widget.game.playTime ?? 0) > 0 && !_isResettingPlayTime) {
        _confirmResetPlayTime();
      }
    } else if (idx == _hideIdx) {
      if (!_isHiding) _hideGame();
    } else if (idx == _deleteIdx) {
      _confirmDeleteGame();
    }
  }

  void _scrollToSelectedItem() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[_selectedIndex];
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

  // ── Cloud sync ──────────────────────────────────────────────────────────

  /// Updates the cloud synchronization authorization for the current ROM.
  Future<void> _toggleCloudSync(bool value) async {
    final syncProvider = widget.syncProvider;
    if (_isUpdatingCloudSync || syncProvider == null) return;
    setState(() => _isUpdatingCloudSync = true);
    try {
      await GameRepository.updateCloudSyncEnabled(
        _targetSystemFolder,
        widget.game.romname,
        value,
      );

      await syncProvider.updateGameCloudSyncEnabled(widget.game.romname, value);

      setState(() => _cloudSyncEnabled = value);

      if (value) {
        final updatedGame = widget.game.copyWith(cloudSyncEnabled: true);
        if (mounted) {
          if (syncProvider is NeoSyncProvider) {
            await (syncProvider as NeoSyncProvider).updateSelectedGame(
              widget.game.romname,
              (romname) async => updatedGame,
            );
          }
          if (mounted) {
            // Trigger an immediate sync-down to ensure the ROM is ready for play.
            await syncProvider.syncGameSavesBeforeLaunch(updatedGame);
          }
        }
      }
      widget.onGameUpdated?.call();
    } catch (e) {
      _log.e('Cloud-sync status update failed: $e');
    } finally {
      if (mounted) setState(() => _isUpdatingCloudSync = false);
    }
  }

  // ── Play time ───────────────────────────────────────────────────────────

  Future<void> _confirmResetPlayTime() async {
    SfxService().playNavSound();
    final confirmed = await ConfirmActionDialog.show(
      context,
      title: AppLocale.resetPlayTimeConfirm.getString(context),
      body: AppLocale.resetPlayTimeConfirmBody.getString(context),
      confirmLabel: AppLocale.reset.getString(context),
      icon: Symbols.timer_off_rounded,
    );
    if (confirmed == true && mounted) {
      _resetPlayTime();
    }
  }

  Future<void> _resetPlayTime() async {
    if (_isResettingPlayTime) return;
    setState(() => _isResettingPlayTime = true);
    try {
      await GameRepository.resetPlayTime(
        _targetSystemFolder,
        widget.game.romname,
      );
      widget.onGameUpdated?.call();
      if (mounted) {
        AppNotification.showNotification(
          context,
          'Play time reset',
          type: NotificationType.success,
        );
      }
    } catch (e) {
      _log.e('Play-time reset operation failed: $e');
    } finally {
      if (mounted) setState(() => _isResettingPlayTime = false);
    }
  }

  // ── Hide ────────────────────────────────────────────────────────────────

  /// Hides the game from every game list.
  ///
  /// Deliberately unconfirmed: nothing is deleted and the game is one visit to
  /// the system's settings dialog away from coming back, so a confirmation
  /// would only get in the way.
  Future<void> _hideGame() async {
    if (_isHiding) return;
    setState(() => _isHiding = true);

    final hiddenRomname = widget.game.romname;
    final displayName = widget.game.name.isNotEmpty
        ? widget.game.name
        : hiddenRomname;
    // Read before the awaits: the dialog is popped as soon as this finishes.
    final databaseProvider = context.read<SqliteDatabaseProvider>();
    final configProvider = context.read<SqliteConfigProvider>();

    try {
      await GameRepository.setGameHidden(
        _targetSystemFolder,
        hiddenRomname,
        true,
      );
      // The systems screen keeps its own cached copies — the recent-games row
      // and the ROM count on the system card — so both are re-read here rather
      // than left showing a game that no longer appears in any list.
      await databaseProvider.loadGamesForSystem(_targetSystemFolder);
      final system = await SystemRepository.getSystemByFolderName(
        _targetSystemFolder,
      );
      if (system != null) await configProvider.refreshSystem(system);
    } catch (e) {
      _log.e('Hiding game failed: $e');
      if (mounted) setState(() => _isHiding = false);
      return;
    }

    if (!mounted) return;
    setState(() => _isHiding = false);

    AppNotification.showNotification(
      context,
      AppLocale.gameHidden
          .getString(context)
          .replaceFirst('{name}', displayName),
      type: NotificationType.info,
    );

    widget.onGameHidden?.call(hiddenRomname);
  }

  // ── Delete ──────────────────────────────────────────────────────────────

  Future<void> _confirmDeleteGame() async {
    SfxService().playNavSound();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => DeleteGameDialog(
        gameName: widget.game.name,
        romName: widget.game.romname,
      ),
    );
    if (confirmed == true && mounted) {
      _deleteGame();
    }
  }

  Future<void> _deleteGame() async {
    if (_isDeleting) return;
    setState(() => _isDeleting = true);

    final targetSystemId = widget.game.systemId ?? widget.system.id;
    final deletedRomname = widget.game.romname;
    // Read before the await: the dialog can be gone by the time deletion ends.
    final rommProvider = context.read<RommProvider>();

    try {
      await GameRepository.deleteGame(
        appSystemId: targetSystemId,
        filename: deletedRomname,
        systemFolderName: _targetSystemFolder,
        romBaseName: deletedRomname,
        romPath: widget.game.romPath,
        fileProvider: widget.fileProvider,
      );
      // Unlink from RomM so the browse grid stops calling it downloaded.
      await rommProvider.forgetLocalDownload(
        romname: deletedRomname,
        systemFolder: _targetSystemFolder,
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

  // ── Build helpers ───────────────────────────────────────────────────────

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canReset = (widget.game.playTime ?? 0) > 0 && !_isResettingPlayTime;

    // If the current selection became disabled (e.g. cloud sync hidden), move to
    // the nearest enabled row without triggering a scroll animation.
    _ensureSelectedIndexEnabled();

    return SingleChildScrollView(
      controller: _scrollController,
      physics: const ClampingScrollPhysics(),
      padding: EdgeInsets.only(bottom: 24.r),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cloud Synchronization Option.
          if (_showCloudSync)
            GestureDetector(
              onTap: () {
                SfxService().playNavSound();
                setState(() => _selectedIndex = _cloudSyncIdx);
                if (!_isUpdatingCloudSync) {
                  _toggleCloudSync(!_cloudSyncEnabled);
                }
              },
              child: SettingRow(
                key: _itemKey(_cloudSyncIdx),
                focused: _selectedIndex == _cloudSyncIdx,
                title: AppLocale.cloudSync.getString(context),
                subtitle: _cloudSyncEnabled
                    ? AppLocale.cloudSyncOn.getString(context)
                    : AppLocale.cloudSyncOff.getString(context),
                trailing: _isUpdatingCloudSync
                    ? SizedBox(
                        width: 20.r,
                        height: 20.r,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: theme.colorScheme.onSurface,
                        ),
                      )
                    : ExcludeFocus(
                        child: CustomToggleSwitch(
                          value: _cloudSyncEnabled,
                          onChanged: !_isUpdatingCloudSync
                              ? (v) => _toggleCloudSync(v)
                              : null,
                          activeColor: theme.colorScheme.primary,
                        ),
                      ),
              ),
            )
          else
            SizedBox.shrink(key: _itemKey(_cloudSyncIdx)),
          SizedBox(height: _showCloudSync ? 12.r : 0.r),

          // Play-time reset.
          GestureDetector(
            onTap: () {
              SfxService().playNavSound();
              setState(() => _selectedIndex = _playTimeIdx);
              if (canReset) _confirmResetPlayTime();
            },
            child: SettingRow(
              key: _itemKey(_playTimeIdx),
              focused: _selectedIndex == _playTimeIdx,
              title: AppLocale.playTime.getString(context),
              subtitle: GameUtils.formatPlayTime(widget.game.playTime ?? 0),
              trailing: _isResettingPlayTime
                  ? SizedBox(
                      width: 20.r,
                      height: 20.r,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onSurface,
                      ),
                    )
                  : Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.r,
                        vertical: 3.r,
                      ),
                      decoration: BoxDecoration(
                        color: canReset
                            ? theme.colorScheme.error.withValues(alpha: 0.15)
                            : theme.colorScheme.onSurface.withValues(
                                alpha: 0.05,
                              ),
                        borderRadius: BorderRadius.circular(4.r),
                        border: Border.all(
                          color: canReset
                              ? theme.colorScheme.error.withValues(alpha: 0.4)
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.1,
                                ),
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
                              : theme.colorScheme.onSurface.withValues(
                                  alpha: 0.3,
                                ),
                        ),
                      ),
                    ),
            ),
          ),

          SizedBox(height: 12.r),

          // Hide game.
          GestureDetector(
            onTap: () {
              SfxService().playNavSound();
              setState(() => _selectedIndex = _hideIdx);
              if (!_isHiding) _hideGame();
            },
            child: SettingRow(
              key: _itemKey(_hideIdx),
              focused: _selectedIndex == _hideIdx,
              title: AppLocale.hideGame.getString(context),
              subtitle: AppLocale.hideGameSubtitle.getString(context),
              trailing: _isHiding
                  ? SizedBox(
                      width: 20.r,
                      height: 20.r,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.onSurface,
                      ),
                    )
                  : Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.r,
                        vertical: 3.r,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.15,
                        ),
                        borderRadius: BorderRadius.circular(4.r),
                        border: Border.all(
                          color: theme.colorScheme.primary.withValues(
                            alpha: 0.4,
                          ),
                          width: 1.r,
                        ),
                      ),
                      child: Text(
                        AppLocale.hide.getString(context),
                        style: TextStyle(
                          fontSize: 11.r,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
            ),
          ),

          SizedBox(height: 12.r),

          // Delete game.
          GestureDetector(
            onTap: () {
              SfxService().playNavSound();
              setState(() => _selectedIndex = _deleteIdx);
              _confirmDeleteGame();
            },
            child: SettingRow(
              key: _itemKey(_deleteIdx),
              focused: _selectedIndex == _deleteIdx,
              title: AppLocale.deleteGame.getString(context),
              subtitle: AppLocale.deleteGameSubtitle.getString(context),
              trailing: _isDeleting
                  ? SizedBox(
                      width: 20.r,
                      height: 20.r,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.error,
                      ),
                    )
                  : Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.r,
                        vertical: 3.r,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4.r),
                        border: Border.all(
                          color: theme.colorScheme.error.withValues(alpha: 0.4),
                          width: 1.r,
                        ),
                      ),
                      child: Text(
                        AppLocale.delete.getString(context),
                        style: TextStyle(
                          fontSize: 11.r,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
