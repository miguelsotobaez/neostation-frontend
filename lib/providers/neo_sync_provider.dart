import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:isolate';
import 'package:path/path.dart' as path;
import 'package:neostation/services/logger_service.dart';
import '../services/neosync/neo_sync_service.dart';
import '../services/neosync/auth_service.dart';
import '../models/neo_sync_models.dart';
import '../widgets/quota_exceeded_dialog.dart';
import '../models/neo_sync_models.dart' as neo_sync;
import '../models/system_model.dart';
import '../models/game_model.dart';
import '../utils/switch_save_detector.dart';
import '../utils/switch_title_extractor.dart';
import '../repositories/system_repository.dart';
import '../repositories/sync_repository.dart';
import '../repositories/game_repository.dart';
import '../repositories/emulator_repository.dart';
import '../repositories/config_repository.dart';
import '../services/config_service.dart';
import '../services/retroarch_config_service.dart';

part 'neosync/neosync_exceptions.dart';
part 'neosync/neosync_status.dart';
part 'neosync/neosync_path_resolver.dart';
part 'neosync/neosync_upload.dart';
part 'neosync/neosync_download.dart';
part 'neosync/neosync_core.dart';

/// Provider responsible for managing the NeoSync cloud save synchronization service.
///
/// Coordinates background synchronization, conflict resolution, storage quota
/// tracking, and per-game sync status. Splitted into multiple part files to
/// manage the complexity of filesystem resolution and network operations.
class NeoSyncProvider extends ChangeNotifier {
  /// Local cache of user files currently stored in the cloud.
  List<NeoSyncFile> _onlineFiles = [];

  /// Whether a network request to fetch the cloud file list is active.
  bool _isLoadingOnlineFiles = false;

  List<NeoSyncFile> get onlineFiles => _onlineFiles;
  bool get isLoadingOnlineFiles => _isLoadingOnlineFiles;

  static final _log = LoggerService.instance;

  /// Optional reference to [AuthService] for credential verification.
  AuthService? _authService;

  /// Low-level network service for NeoSync API interactions.
  final NeoSyncService _neoSyncService;

  NeoSyncProvider(this._neoSyncService);

  /// Whether a global synchronization task is currently active.
  bool _isSyncing = false;

  /// Overall progress of the current sync operation (0.0 to 1.0).
  double _syncProgress = 0.0;

  /// Human-readable status message for the sync operation.
  String _syncStatus = '';

  /// Total number of files identified for processing in the current task.
  int _totalFiles = 0;

  /// Count of files that have been analyzed (scanned).
  int _processedFiles = 0;

  /// Count of files successfully uploaded to the cloud.
  int _uploadedFiles = 0;

  /// Count of files skipped (already up to date).
  int _skippedFiles = 0;

  /// Count of files successfully downloaded from the cloud.
  int _downloadedFiles = 0;

  /// History of item identifiers processed in the current session.
  List<String> _processedItems = [];

  /// Whether background synchronization is globally enabled.
  bool _autoSyncEnabled = true;

  /// Whether a background (non-interactive) sync is currently active.
  bool _isAutoSyncing = false;

  /// Consecutive failed upload attempts due to storage quota limits.
  int _quotaExceededAttempts = 0;

  /// Whether the user has already been notified of a quota issue in the current session.
  bool _quotaExceededDialogShown = false;

  /// Global flag indicating that a quota limit was recently hit.
  bool _quotaExceededActive = false;

  /// Real-time synchronization state for individual games, keyed by unique ID.
  final Map<String, neo_sync.GameSyncState> _gameSyncStates = {};

  /// Cache of local save file metadata, grouped by game.
  final Map<String, List<LocalSaveFile>> _gameLocalSaves = {};

  /// Cache of cloud save file metadata, grouped by game.
  final Map<String, List<NeoSyncFile>> _gameCloudSaves = {};

  /// Set of platform-specific files (e.g., PS2 memory cards, Switch user saves) already handled.
  final Set<String> _processedMultiEmulatorFilesInSession = {};

  /// Identifier of the game ROM currently targeted for per-game sync UI.
  String? _selectedGameRomname;

  /// Human-readable name of the game currently targeted.
  String? _selectedGameName;

  /// All metadata for files discovered during the sync process.
  List<NeoSyncFile> _files = [];

  /// Current user's storage quota and usage metadata.
  NeoSyncQuota? _quota;

  /// Last error message encountered during synchronization.
  String? _error;

  // Getters
  bool get isSyncing => _isSyncing;
  double get syncProgress => _syncProgress;
  String get syncStatus => _syncStatus;
  int get totalFiles => _totalFiles;
  int get processedFiles => _processedFiles;
  int get uploadedFiles => _uploadedFiles;
  int get skippedFiles => _skippedFiles;
  int get downloadedFiles => _downloadedFiles;
  List<String> get processedItems => _processedItems;

  bool get autoSyncEnabled => _autoSyncEnabled;
  bool get isAutoSyncing => _isAutoSyncing;

  int get quotaExceededAttempts => _quotaExceededAttempts;
  bool get quotaExceededDialogShown => _quotaExceededDialogShown;

  String? get error => _error;
  NeoSyncQuota? get quota => _quota;
  List<NeoSyncFile> get files => _files;
  bool get isLoading => false;

  /// Retrieves the current sync state for a specific game.
  neo_sync.GameSyncState? getGameSyncState(String gameId) =>
      _gameSyncStates[gameId];

  /// Returns the list of local save files detected for a specific game.
  List<LocalSaveFile> getGameLocalSaves(String gameId) =>
      _gameLocalSaves[gameId] ?? [];

  /// Returns the list of cloud save files found for a specific game.
  List<NeoSyncFile> getGameCloudSaves(String gameId) =>
      _gameCloudSaves[gameId] ?? [];

  /// Internal bridge to allow [part] files to trigger UI updates.
  void notify() {
    notifyListeners();
  }

  /// Internal helper to update the global sync state.
  void _setSyncing(bool syncing) {
    _isSyncing = syncing;
    notifyListeners();
  }

  /// Internal helper to update the background sync state.
  void _setAutoSyncing(bool autoSyncing) {
    _isAutoSyncing = autoSyncing;
    notifyListeners();
  }

  /// Derives a game identifier or title from its filesystem path.
  String _extractGameNameFromPath(String filePath) {
    final fileName = path.basename(filePath);
    if (fileName.contains('.')) {
      return fileName.substring(0, fileName.lastIndexOf('.'));
    }
    return fileName;
  }

  /// Analyzes an error message to determine if it represents a storage quota violation.
  ///
  /// Increments failure counters if a quota issue is detected.
  bool _checkQuotaExceeded(String errorMessage) {
    final lowerMessage = errorMessage.toLowerCase();
    if (lowerMessage.contains('quota') ||
        lowerMessage.contains('storage') ||
        lowerMessage.contains('413') ||
        lowerMessage.contains('full')) {
      _quotaExceededAttempts++;
      return true;
    }
    return false;
  }

  /// Resets quota-related failure counters and status flags.
  void _resetQuotaAttempts() {
    _quotaExceededAttempts = 0;
    _quotaExceededActive = false;
  }

  /// Downloads a file from NeoSync storage and writes it to the local filesystem.
  ///
  /// Upon successful download, it synchronizes the local database sync state
  /// to match the cloud version.
  Future<void> _downloadCloudFile(NeoSyncFile cloudFile, File localFile) async {
    final result = await _neoSyncService.downloadFile(cloudFile.id);
    if (result['success'] == true && result['data'] != null) {
      final bytes = result['data'] as List<int>;
      await localFile.writeAsBytes(bytes);

      try {
        final stat = await localFile.stat();
        await SyncRepository.saveSyncState(
          localFile.path,
          stat.modified.millisecondsSinceEpoch,
          cloudFile.fileModifiedAtTimestamp ?? 0,
          stat.size,
          fileHash: cloudFile.checksum,
        );
      } catch (e) {
        _log.w('Could not save sync state for ${localFile.path}: $e');
      }
    } else {
      throw Exception(result['message'] ?? 'Failed to download file');
    }
  }

  /// Resolves the [SystemModel] associated with a specific game.
  ///
  /// Performs a database lookup if system metadata is missing from the [GameModel].
  Future<SystemModel?> _getSystemForGame(GameModel game) async {
    try {
      String? folderName = game.systemFolderName;

      folderName ??= await GameRepository.getSystemFolderForGame(game.romname);

      if (folderName == null) return null;

      try {
        return await SystemRepository.getSystemByFolderName(folderName);
      } catch (e) {
        _log.e('System $folderName not found in database: $e');
        return null;
      }
    } catch (e) {
      _log.e('Error getting system for game: $e');
    }
    return null;
  }
}
