part of '../neo_sync_provider.dart';

extension NeoSyncDownload on NeoSyncProvider {
  /// Auto-sync para descargas (archivos de la nube que no están localmente o son más nuevos)
  Future<void> autoSyncDownloads() async {
    if (!isNeoSyncAuthenticated) {
      return;
    }
    if (_isSyncing) return;

    _setSyncing(true);
    _error = null;
    _syncProgress = 0.0;
    _syncStatus = 'Fetching cloud files...';
    _totalFiles = 0;
    _processedFiles = 0;
    _downloadedFiles = 0;
    _processedItems = [];
    notify();

    try {
      final result = await _neoSyncService.getAllFiles();
      if (!result['success']) {
        throw Exception('Failed to fetch cloud files: ${result['message']}');
      }

      final cloudFiles = result['files'] as List<NeoSyncFile>;
      if (cloudFiles.isEmpty) {
        _syncStatus = 'No cloud files found';
        _processedItems.add('No cloud files found for auto-sync');
        _setSyncing(false);
        return;
      }

      _totalFiles = cloudFiles.length;
      _processedItems.add('Auto-syncing $_totalFiles cloud files...');
      _syncStatus = 'Checking cloud files...';
      notify();

      // Collect RetroArch folders to resolve locally
      final savesPath = await _getRetroArchSavesPath();

      for (final cloudFile in cloudFiles) {
        await _processAutoDownloadFile(cloudFile, savesPath ?? '');
        _processedFiles++;
        _syncProgress = _totalFiles > 0 ? _processedFiles / _totalFiles : 0.0;
        notify();
      }

      _syncProgress = 1.0;
      _syncStatus =
          'Auto-download completed: $_downloadedFiles files downloaded';
      _processedItems.add(
        'Auto-download completed: $_downloadedFiles files downloaded',
      );
    } catch (e) {
      _error = 'Error during auto-sync download: $e';
      _syncStatus = 'Error: $_error';
      _processedItems.add('Auto-sync download error: $e');
      NeoSyncProvider._log.e('Auto-sync downloads error: $e');
    } finally {
      _setSyncing(false);
    }
  }

  /// Fase 2: Descargar archivos de la nube
  Future<void> _performDownloadPhase(String savesPath) async {
    _syncStatus = 'Phase 2: Downloading cloud files...';
    _processedItems.add('⬇️ Phase 2: Downloading files from cloud...');
    notify();

    final result = await _neoSyncService.getAllFiles();
    if (!result['success']) {
      throw Exception('Failed to fetch cloud files: ${result['message']}');
    }

    final cloudFiles = result['files'] as List<NeoSyncFile>;
    if (cloudFiles.isEmpty) {
      _processedItems.add('No cloud files found');
      return;
    }

    _processedItems.add('⬇️ Found ${cloudFiles.length} cloud files to process');

    for (final cloudFile in cloudFiles) {
      await _processDownloadFileWithConflictDetection(cloudFile, savesPath);
      _processedFiles++;
      _syncProgress = _totalFiles > 0 ? _processedFiles / _totalFiles : 0.0;
      notify();
    }
  }

  /// Procesa un archivo para auto-descarga (Universal)
  Future<void> _processAutoDownloadFile(
    NeoSyncFile cloudFile,
    String savesPath,
  ) async {
    try {
      // NeoSync v2 paths (`saves/<system>/<emulator>/<scope>/...`) carry the
      // emulator slug. Shared memory-card files route directly to the
      // configured custom folder; per-game files fall through to the normal
      // game lookup below.
      final v2Path = CloudPathBuilder.parse(cloudFile.fileName);
      if (v2Path != null && v2Path.isShared) {
        final customFolder = await NeoSyncSaveFolderRepository.getFolder(
          v2Path.system,
          v2Path.emulatorSlug,
        );
        if (customFolder != null && customFolder.isNotEmpty) {
          final localFile = File(path.join(customFolder, v2Path.filePath));
          await localFile.parent.create(recursive: true);
          if (!localFile.existsSync() ||
              cloudFile.uploadedAt.isAfter(await localFile.lastModified())) {
            await _downloadCloudFileImpl(cloudFile, localFile);
            _downloadedFiles++;
            _processedItems.add('⬇️ Custom save: ${cloudFile.fileName}');
          } else {
            _skippedFiles++;
          }
          return;
        }
      }

      // 1. Resolve the game associated with the file
      GameModel? game = await _findGameForCloudFile(cloudFile);

      if (game == null) {
        NeoSyncProvider._log.w(
          'Could not identify game for cloud file: ${cloudFile.fileName}',
        );
        return;
      }

      // 2. Resolve local path using the universal system
      final localPaths = await resolveCloudFileToLocalPath(game, cloudFile);

      if (localPaths.isEmpty) return;

      for (final localPath in localPaths) {
        final localFile = File(localPath);
        if (localFile.existsSync()) {
          final localStat = await localFile.stat();
          if (cloudFile.uploadedAt.isAfter(localStat.modified)) {
            await _downloadCloudFileImpl(cloudFile, localFile);
            _downloadedFiles++;
            _processedItems.add('⬇️ Auto-updated: ${cloudFile.fileName}');
          } else {
            _skippedFiles++;
          }
        } else {
          await localFile.parent.create(recursive: true);
          await _downloadCloudFileImpl(cloudFile, localFile);
          _downloadedFiles++;
          _processedItems.add('✨ Auto-downloaded new: ${cloudFile.fileName}');
        }
      }
    } catch (e) {
      _processedItems.add('Error downloading ${cloudFile.fileName}: $e');
    }
  }

  /// Helper para encontrar el juego de un archivo de nube
  Future<GameModel?> _findGameForCloudFile(NeoSyncFile cloudFile) async {
    final parts = cloudFile.fileName.split('/');

    // Identify if it is a Switch file based on known prefixes
    final isSwitchPath =
        cloudFile.fileName.startsWith('saves/switch/') ||
        cloudFile.fileName.startsWith('saves/eden/') ||
        cloudFile.fileName.startsWith('saves/citron/') ||
        cloudFile.fileName.startsWith('saves/yuzu/') ||
        cloudFile.fileName.startsWith('saves/suyu/') ||
        cloudFile.fileName.startsWith('saves/sudachi/');

    if (isSwitchPath && parts.length >= 3) {
      final gameNameInPath = parts[2];
      try {
        final row = await GameRepository.findSwitchGameByName(gameNameInPath);
        if (row != null) {
          final romname = row['filename'].toString();
          final title = row['title_name']?.toString();
          final titleId = row['title_id']?.toString();
          final romPath = row['rom_path']?.toString();

          return GameModel(
            name: title ?? romname,
            realname: title ?? romname,
            romname: romname,
            romPath: romPath,
            titleName: title,
            systemFolderName: 'switch',
            systemId: 'switch',
            year: '',
            developer: '',
            publisher: '',
            genre: '',
            players: '',
            rating: 0.0,
          ).copyWith(titleId: titleId);
        }
      } catch (e) {
        NeoSyncProvider._log.e('Error finding Switch game by name: $e');
      }
    }

    {
      final name = path.basenameWithoutExtension(cloudFile.fileName);
      // Attempt to search in DB
      try {
        final row = await GameRepository.findRomByFilenamePrefix(name);
        if (row != null) {
          final romname = row['filename'].toString();
          final title = row['title_name']?.toString();
          final sysFolder = row['folder_name']?.toString() ?? '';

          return GameModel(
            name: title ?? romname,
            realname: title ?? romname,
            romname: romname,
            systemFolderName: sysFolder,
            year: '',
            developer: '',
            publisher: '',
            genre: '',
            players: '',
            rating: 0.0,
          );
        }
      } catch (e) {
        NeoSyncProvider._log.e('Error finding game for file: $e');
      }
    }
    return null;
  }

  /// Descarga un archivo de la nube
  Future<void> _downloadCloudFileImpl(
    NeoSyncFile cloudFile,
    File localFile,
  ) async {
    final result = await _neoSyncService.downloadFile(cloudFile.id);
    if (result['success'] == true && result['data'] != null) {
      final bytes = result['data'] as List<int>;
      await localFile.writeAsBytes(bytes);

      // Save the actual local sync state in the database.
      // This avoids the "Operation not permitted" error on Android 11+ when trying
      // to change the timestamp with setLastModified.
      try {
        final stat = await localFile.stat();
        await SyncRepository.saveSyncState(
          NeoSyncProvider.kSyncProviderId,
          localFile.path,
          stat.modified.millisecondsSinceEpoch,
          cloudFile.fileModifiedAtTimestamp ?? 0,
          stat.size,
          fileHash: cloudFile.checksum,
        );
      } catch (e) {
        NeoSyncProvider._log.w(
          'Could not save sync state for ${localFile.path}: $e',
        );
      }
    } else {
      throw Exception(result['message'] ?? 'Failed to download file');
    }
  }

  /// Procesa descarga con detección de conflictos
  Future<void> _processDownloadFileWithConflictDetection(
    NeoSyncFile cloudFile,
    String savesPath,
  ) async {
    GameModel? game = await _findGameForCloudFile(cloudFile);
    if (game == null) return;

    final localPaths = await resolveCloudFileToLocalPath(game, cloudFile);

    if (localPaths.isEmpty) return;

    for (final localPath in localPaths) {
      final localFile = File(localPath);
      if (localFile.existsSync()) {
        final localStat = await localFile.stat();
        if (cloudFile.uploadedAt.isAfter(localStat.modified)) {
          await _downloadCloudFileImpl(cloudFile, localFile);
          _downloadedFiles++;
          _processedItems.add('⬇️ Updated: ${cloudFile.fileName}');
        } else {
          _skippedFiles++;
        }
      } else {
        await localFile.parent.create(recursive: true);
        await _downloadCloudFileImpl(cloudFile, localFile);
        _downloadedFiles++;
        _processedItems.add('✨ Downloaded: ${cloudFile.fileName}');
      }
    }
  }
}
