import 'dart:io';
import 'package:neostation/services/logger_service.dart';
import '../models/database_game_model.dart';
import '../data/datasources/sqlite_database_service.dart';
import '../data/datasources/sqlite_service.dart';
import '../providers/file_provider.dart';
import '../services/saf_directory_service.dart';

/// Repository for game data access operations.
class GameRepository {
  /// Returns all games grouped by system folder name.
  static Future<Map<String, List<DatabaseGameModel>>> loadDatabase() =>
      SqliteDatabaseService.loadDatabase();

  /// Returns all games registered for [systemFolderName].
  static Future<List<DatabaseGameModel>> loadGamesForSystem(
    String systemFolderName,
  ) => SqliteDatabaseService.loadGamesForSystem(systemFolderName);

  /// Toggles favorite status for a game.
  static Future<void> toggleFavorite(
    String systemFolderName,
    String filename,
  ) => SqliteDatabaseService.toggleFavorite(systemFolderName, filename);

  /// Records that a game was played (updates timestamp and play stats).
  static Future<void> recordGamePlayed(
    String systemFolderName,
    String filename,
  ) => SqliteDatabaseService.recordGamePlayed(systemFolderName, filename);

  /// Persists updated metadata for a game.
  static Future<void> updateGame(
    String systemFolderName,
    DatabaseGameModel updatedGame,
  ) => SqliteDatabaseService.updateGame(systemFolderName, updatedGame);

  /// Returns global stats: totalSystems, totalRoms, favoriteRoms, playedRoms.
  static Future<Map<String, dynamic>> getStats() =>
      SqliteDatabaseService.getStats();

  /// Returns ROM counts keyed by system folder name.
  static Future<Map<String, int>> getRomCounts() =>
      SqliteDatabaseService.getRomCounts();

  /// Removes all ROM entries associated with a specific folder path.
  static Future<int> deleteRomsByFolderPath(String folderPath) =>
      SqliteService.deleteRomsByFolderPath(folderPath);

  /// Permanently deletes a game, its database metadata, and all associated
  /// scraped media files (screenshots, fanart, wheel, boxart, video) from disk.
  static Future<void> deleteGame({
    String? appSystemId,
    required String filename,
    required String systemFolderName,
    required String romBaseName,
    String? romPath,
    FileProvider? fileProvider,
  }) async {
    final log = LoggerService.instance;

    if (appSystemId == null) {
      log.e('deleteGame: appSystemId is null, cannot delete from DB');
      return;
    }
    await SqliteService.deleteGame(appSystemId, filename);

    if (romPath != null) {
      try {
        if (romPath.startsWith('content://') &&
            await SafDirectoryService.deleteFile(romPath)) {
          log.i('deleteGame: Deleted ROM file via SAF: $romPath');
        } else {
          final romFile = File(romPath);
          if (await romFile.exists()) {
            await romFile.delete();
            log.i('deleteGame: Deleted ROM file: $romPath');
          } else {
            log.w('deleteGame: ROM file not found: $romPath');
          }
        }
      } catch (e) {
        log.e('deleteGame: Failed to delete ROM file $romPath: $e');
      }
    } else {
      log.w('deleteGame: romPath is null, skipping ROM file deletion');
    }

    final mediaDir = fileProvider?.getMediaDirectoryPath();
    if (mediaDir == null) {
      log.w('deleteGame: mediaDir is null, skipping scraped media deletion');
      return;
    }

    // Media files are stored using the ROM name WITHOUT extension
    final strippedBase = _stripExtension(romBaseName);
    final strippedFilename = _stripExtension(filename);

    const mediaTypes = ['screenshots', 'fanarts', 'wheels', 'box2d', 'videos'];
    const extensions = ['png', 'jpg', 'jpeg', 'webp', 'mp4'];
    int deletedMedia = 0;

    for (final type in mediaTypes) {
      final folder = Directory('$mediaDir/$systemFolderName/$type');
      try {
        if (!await folder.exists()) continue;
        final files = await folder.list().toList();
        for (final entity in files) {
          if (entity is File) {
            final name = entity.uri.pathSegments.last;
            final base = name.contains('.')
                ? name.substring(0, name.lastIndexOf('.'))
                : name;
            if (base == strippedBase ||
                base == strippedFilename ||
                base == romBaseName ||
                base == filename) {
              final ext = name.contains('.')
                  ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
                  : '';
              if (extensions.contains(ext)) {
                await entity.delete();
                deletedMedia++;
              }
            }
          }
        }
      } catch (e) {
        log.e('deleteGame: Error deleting $type media for $filename: $e');
      }
    }

    if (deletedMedia > 0) {
      log.i(
        'deleteGame: Deleted $deletedMedia scraped media files for $filename',
      );
    }
  }

  // ── Single ROM operations ─────────────────────────────────────────────────

  static Future<DatabaseGameModel?> getSingleGame(
    String systemId,
    String filename,
  ) => SqliteService.getSingleGame(systemId, filename);

  static Future<List<DatabaseGameModel>> getAllGames() =>
      SqliteService.getAllGames();

  static Future<List<DatabaseGameModel>> getFavoriteGames() =>
      SqliteService.getFavoriteGames();

  static Future<List<DatabaseGameModel>> getGamesBySystem(String systemId) =>
      SqliteService.getGamesBySystem(systemId);

  static Future<void> updatePlayTime(String romPath, int seconds) =>
      SqliteService.updatePlayTime(romPath, seconds);

  static Future<void> toggleRomFavoriteByPath(String romPath) =>
      SqliteService.toggleRomFavorite(romPath);

  static Future<void> recordRomPlayedByPath(String romPath) =>
      SqliteService.recordRomPlayed(romPath);

  // ── Sync-related ROM lookups ───────────────────────────────────────────────

  /// Returns the system folder_name for a game by exact romname, or null.
  static Future<String?> getSystemFolderForGame(String romname) async {
    final db = await SqliteService.getDatabase();
    final result = await db.rawQuery(
      '''
      SELECT s.folder_name
      FROM user_roms ur
      JOIN app_systems s ON ur.app_system_id = s.id
      WHERE ur.filename = ?
      LIMIT 1
      ''',
      [romname],
    );
    return result.isNotEmpty ? result.first['folder_name']?.toString() : null;
  }

  /// Returns the raw app_system_id for a game by exact romname, or null.
  static Future<String?> getSystemIdForGame(String romname) async {
    final db = await SqliteService.getDatabase();
    final result = await db.query(
      'user_roms',
      columns: ['app_system_id'],
      where: 'filename = ?',
      whereArgs: [romname],
      limit: 1,
    );
    return result.isNotEmpty ? result.first['app_system_id']?.toString() : null;
  }

  /// Finds a Switch ROM matching [nameQuery] by title_name or filename prefix.
  /// Returns {filename, title_name, title_id, rom_path} or null.
  static Future<Map<String, dynamic>?> findSwitchGameByName(
    String nameQuery,
  ) async {
    final db = await SqliteService.getDatabase();
    final result = await db.rawQuery(
      '''
      SELECT filename, title_name, title_id, rom_path
      FROM user_roms
      WHERE (title_name LIKE ? OR filename LIKE ?)
        AND app_system_id = 'switch'
      LIMIT 1
      ''',
      ['%$nameQuery%', '$nameQuery%'],
    );
    return result.isNotEmpty ? Map<String, dynamic>.from(result.first) : null;
  }

  /// Finds a ROM by filename prefix and returns {filename, title_name, folder_name} or null.
  static Future<Map<String, dynamic>?> findRomByFilenamePrefix(
    String prefix,
  ) async {
    final db = await SqliteService.getDatabase();
    final result = await db.rawQuery(
      '''
      SELECT ur.filename, ur.title_name, s.folder_name
      FROM user_roms ur
      JOIN app_systems s ON ur.app_system_id = s.id
      WHERE ur.filename LIKE ?
      LIMIT 1
      ''',
      ['$prefix%'],
    );
    return result.isNotEmpty ? Map<String, dynamic>.from(result.first) : null;
  }

  /// Finds a Switch ROM by [titleId]. Returns {filename, title_name} or null.
  static Future<Map<String, dynamic>?> findSwitchGameByTitleId(
    String titleId,
  ) async {
    final db = await SqliteService.getDatabase();
    final result = await db.rawQuery(
      '''
      SELECT ur.filename, ur.title_name
      FROM user_roms ur
      JOIN app_systems s ON ur.app_system_id = s.id
      WHERE UPPER(ur.title_id) = UPPER(?) AND s.folder_name = ?
      LIMIT 1
      ''',
      [titleId, 'switch'],
    );
    return result.isNotEmpty ? Map<String, dynamic>.from(result.first) : null;
  }

  /// Returns the title_id for a game using flexible filename/title matching, or null.
  static Future<String?> getTitleIdForGame(
    String romname,
    String gameName,
  ) async {
    final db = await SqliteService.getDatabase();
    final result = await db.rawQuery(
      'SELECT title_id FROM user_roms WHERE filename = ? OR filename LIKE ? OR title_name LIKE ? LIMIT 1',
      [romname, '$romname.%', '%$gameName%'],
    );
    if (result.isNotEmpty && result.first['title_id'] != null) {
      return result.first['title_id'].toString();
    }
    return null;
  }

  /// Persists a [titleId] for the ROM identified by [romname].
  static Future<void> updateGameTitleId(String romname, String titleId) async {
    final db = await SqliteService.getDatabase();
    await db.rawUpdate('UPDATE user_roms SET title_id = ? WHERE filename = ?', [
      titleId,
      romname,
    ]);
  }

  /// Returns whether cloud sync is enabled for a ROM.
  static Future<bool> isCloudSyncEnabled(
    String systemFolderName,
    String romname,
  ) => SqliteService.isRomCloudSyncEnabled(systemFolderName, romname);

  /// Sets cloud sync enabled state for a ROM.
  static Future<void> updateCloudSyncEnabled(
    String systemFolderName,
    String romname,
    bool enabled,
  ) => SqliteService.updateRomCloudSyncEnabled(
    systemFolderName,
    romname,
    enabled,
  );

  /// Resets play time and last played timestamp for a ROM.
  static Future<void> resetPlayTime(String systemFolderName, String romname) =>
      SqliteService.resetRomPlayTime(systemFolderName, romname);

  /// Sets per-ROM emulator override.
  static Future<void> setEmulatorOverride(
    String systemFolderName,
    String romname,
    String? emulatorUniqueId,
    int? emulatorOsId,
  ) => SqliteService.setRomEmulatorOverride(
    systemFolderName,
    romname,
    emulatorUniqueId,
    emulatorOsId,
  );

  /// Returns the localized description for a ROM.
  static Future<String> getLocalizedDescription(
    String romname,
    String systemId,
  ) => SqliteService.getLocalizedGameDescription(romname, systemId);

  /// Updates the box2d aspect ratio for a specific game.
  static Future<void> updateBox2dAspectRatio(
    String systemId,
    String filename,
    String ratio,
  ) => SqliteService.updateBox2dAspectRatio(systemId, filename, ratio);

  /// Strips the last file extension from a filename.
  static String _stripExtension(String name) {
    final dot = name.lastIndexOf('.');
    return dot == -1 ? name : name.substring(0, dot);
  }
}
