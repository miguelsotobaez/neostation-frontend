import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../data/datasources/sqlite_service.dart';
import '../models/database_game_model.dart';
import '../models/retro_achievements_dashboard_models.dart';

/// Repository for RetroAchievements data access.
class RetroAchievementsRepository {
  static const String _raApiKeyStorageKey = 'ra_api_key';
  // Do not let a transient Android Keystore error erase credentials. This can
  // happen during cold boot on some launchers, and the default resetOnError
  // behaviour turns a temporary read failure into a permanent logout.
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false, migrateWithBackup: true),
    // NeoStation's macOS builds are also distributed outside the App Store.
    // The classic Keychain remains encrypted by macOS without requiring the
    // restricted Keychain Sharing entitlement used by the data-protection
    // Keychain, so ad-hoc-signed builds can persist the API key securely.
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  /// Returns local ROM counts: total and RA-compatible (has ra_hash).
  static Future<({int totalRoms, int raCompatibleRoms})>
  getLocalRomStats() async {
    final db = await SqliteService.getDatabase();

    final totalResult = await db.rawQuery(
      'SELECT COUNT(*) as total FROM user_roms',
    );
    final compatibleResult = await db.rawQuery('''
      SELECT COUNT(*) as compatible
      FROM user_roms
      WHERE ra_hash IS NOT NULL AND ra_hash != ''
    ''');

    return (
      totalRoms:
          int.tryParse(totalResult.first['total']?.toString() ?? '0') ?? 0,
      raCompatibleRoms:
          int.tryParse(
            compatibleResult.first['compatible']?.toString() ?? '0',
          ) ??
          0,
    );
  }

  /// Returns the persisted RA username, or null if not set.
  static Future<String?> getRAUser() async {
    final config = await SqliteService.getUserConfig();
    final value = config?['ra_user']?.toString();
    return (value != null && value.isNotEmpty) ? value : null;
  }

  /// Persists the RA username.
  static Future<void> saveRAUser(String username) =>
      SqliteService.updateRAUser(username);

  /// Persists the RA API key securely.
  static Future<void> saveRAApiKey(String apiKey) async {
    await _storage.write(key: _raApiKeyStorageKey, value: apiKey);
  }

  /// Returns the persisted RA API key, or null if not set.
  static Future<String?> getRAApiKey() async {
    return _storage.read(key: _raApiKeyStorageKey);
  }

  /// Clears the stored RA API key.
  static Future<void> clearRAApiKey() async {
    await _storage.delete(key: _raApiKeyStorageKey);
  }

  /// Clears the stored RA username.
  static Future<void> clearRAUser() async {
    final db = await SqliteService.getDatabase();
    await db.update('user_config', {'ra_user': null});
  }

  // ── ROM RA hash operations ────────────────────────────────────────────────

  static Future<String?> getRomRaHash(String romPath) =>
      SqliteService.getRomRaHash(romPath);

  static Future<void> updateRomRaHash(String romPath, String hash) =>
      SqliteService.updateRomRaHash(romPath, hash);

  /// How a ROM's RetroAchievements match was established. Persisted in
  /// `user_roms.ra_match_source`; only [raMatchManual] survives an automatic
  /// re-match.
  static const String raMatchHash = 'hash';
  static const String raMatchFilename = 'filename';
  static const String raMatchTitle = 'title';
  static const String raMatchManual = 'manual';

  /// SQL fragment guarding automatic writes against overwriting a user's pick.
  static const String _notManuallyMatched =
      "(ra_match_source IS NULL OR ra_match_source != '$raMatchManual')";

  static Future<void> updateRomRaGameId(
    String romPath,
    int? gameId, {
    String matchSource = raMatchHash,
  }) async {
    final db = await SqliteService.getDatabase();
    await db.rawUpdate(
      'UPDATE user_roms SET id_ra = ?, ra_match_source = ? '
      'WHERE rom_path = ? AND $_notManuallyMatched',
      [gameId, matchSource, romPath],
    );
  }

  /// Records a match the user chose by hand. Unlike the automatic paths this
  /// always writes, and marks the row so later re-match passes leave it alone.
  static Future<void> setManualRomRaMatch(String romPath, int gameId) async {
    final db = await SqliteService.getDatabase();
    await db.rawUpdate(
      'UPDATE user_roms SET id_ra = ?, ra_match_source = ? WHERE rom_path = ?',
      [gameId, raMatchManual, romPath],
    );
  }

  /// Clears a manual override so the ROM is eligible for automatic matching again.
  static Future<void> clearManualRomRaMatch(String romPath) async {
    final db = await SqliteService.getDatabase();
    await db.rawUpdate(
      'UPDATE user_roms SET id_ra = NULL, ra_match_source = NULL '
      'WHERE rom_path = ?',
      [romPath],
    );
  }

  /// Returns the match source for [romPath], or null if never matched.
  static Future<String?> getRomRaMatchSource(String romPath) async {
    final db = await SqliteService.getDatabase();
    final rows = await db.rawQuery(
      'SELECT ra_match_source FROM user_roms WHERE rom_path = ? LIMIT 1',
      [romPath],
    );
    if (rows.isEmpty) return null;
    return rows.first['ra_match_source']?.toString();
  }

  // ── Game ID lookups (for RA game matching) ────────────────────────────────

  /// Resolves RA game_id by MD5 hash, preferring the ROM's own console.
  ///
  /// Falls back to a console-agnostic lookup when the scoped one finds
  /// nothing. An MD5 is unique in practice, so restricting it to one console
  /// buys no safety — it only loses matches whenever a ROM sits in a folder
  /// whose RA console differs from the one its set is registered under: 32X
  /// titles kept in a Mega Drive folder, a Game Boy set for a ROM filed under
  /// Game Boy Color, an SG-1000 title in a Master System folder. Those are
  /// correct matches for the exact dump, and the lazy per-game path already
  /// accepted them, so the scoped-only lookup just made the two paths
  /// disagree.
  static Future<int?> getGameIdByHash(String raHash, String raConsoleId) async {
    final scoped = await SqliteService.getRetroAchievementsGameIdByHash(
      raHash,
      raConsoleId,
    );
    if (scoped != null && scoped != 0) return scoped;

    final anyConsole = await findGameIdByHash(raHash);
    return (anyConsole == null || anyConsole == 0) ? null : anyConsole;
  }

  // ── ROM RA-data update ─────────────────────────────────────────────────────

  /// Finds a matching entry in app_ra_game_list by [consoleName] LIKE and
  /// [titleLikePattern] LIKE. Normal games are preferred over subsets and
  /// hacks, unless [preferHackMatches] is true. Returns {hash, gameId} or null.
  static Future<({String hash, int? gameId})?> findRAHashByConsoleName(
    String consoleName,
    String titleLikePattern, {
    bool preferHackMatches = false,
  }) async {
    final db = await SqliteService.getDatabase();
    final results = await db.rawQuery(
      '''
      SELECT hash, game_id
      FROM app_ra_game_list
      WHERE console_name LIKE ? AND title LIKE ?
      ORDER BY
        CASE
          WHEN ? = 1 AND title LIKE '~Hack~%' THEN 0
          WHEN ? = 1 THEN 1
          WHEN ? = 0 AND title LIKE '~Hack~%' THEN 1
          ELSE 0
        END,
        CASE WHEN title LIKE '%[Subset%' THEN 1 ELSE 0 END,
        LENGTH(title) ASC,
        title ASC
      LIMIT 1
      ''',
      [
        '%$consoleName%',
        titleLikePattern,
        preferHackMatches ? 1 : 0,
        preferHackMatches ? 1 : 0,
        preferHackMatches ? 1 : 0,
      ],
    );
    if (results.isEmpty) return null;
    return (
      hash: results.first['hash'].toString(),
      gameId: int.tryParse(results.first['game_id']?.toString() ?? ''),
    );
  }

  /// Updates user_roms ra_hash and id_ra for a ROM identified by [filename] and [systemId].
  ///
  /// The hash is always refreshed; the match itself is left alone when the user
  /// set it by hand, so a re-hash pass never discards a manual choice.
  static Future<void> updateRomRAData(
    String filename,
    String systemId,
    String hash,
    int? gameId, {
    String matchSource = raMatchHash,
  }) async {
    final db = await SqliteService.getDatabase();
    await db.rawUpdate(
      'UPDATE user_roms SET ra_hash = ? WHERE filename = ? AND app_system_id = ?',
      [hash, filename, systemId],
    );
    await db.rawUpdate(
      'UPDATE user_roms SET id_ra = ?, ra_match_source = ? '
      'WHERE filename = ? AND app_system_id = ? AND $_notManuallyMatched',
      [gameId, matchSource, filename, systemId],
    );
  }

  // ── Game ID lookups (for RA game matching) ────────────────────────────────

  /// Finds RA game_id by exact MD5 hash match in app_ra_game_list.
  /// Returns 0 (not found) or the game_id.
  static Future<int?> findGameIdByHash(String md5Hash) async {
    final db = await SqliteService.getDatabase();
    final results = await db.rawQuery(
      '''
      SELECT game_id
      FROM app_ra_game_list
      WHERE hash COLLATE NOCASE = ?
      LIMIT 1
      ''',
      [md5Hash],
    );
    if (results.isEmpty) return null;
    return int.tryParse(results.first['game_id']?.toString() ?? '0') ?? 0;
  }

  /// Finds RA game_id by filename for a system, using exact then LIKE matching.
  /// [filenameWithoutExt] should already be sanitized (no brackets/parens).
  /// Returns the game_id, or null if not found.
  static Future<int?> findGameIdByFilename(
    String systemFolderName,
    String filenameWithoutExt,
  ) async {
    final db = await SqliteService.getDatabase();

    const consoleSubquery = '''
      SELECT asys.ra_id
      FROM app_systems asys
      WHERE asys.folder_name = ?
    ''';

    // Exact title match
    final exactResults = await db.rawQuery(
      '''
      SELECT g.game_id
      FROM app_ra_game_list g
      WHERE g.console_id = ($consoleSubquery)
        AND g.title = ?
      ORDER BY g.title DESC
      LIMIT 1
      ''',
      [systemFolderName, filenameWithoutExt],
    );
    if (exactResults.isNotEmpty) {
      return int.tryParse(exactResults.first['game_id']?.toString() ?? '0') ??
          0;
    }

    // LIKE match with normalized search pattern
    final searchPattern =
        '%${filenameWithoutExt.replaceAll(' - ', ' ').replaceAll(':', '').replaceAll(' ', '%').trim()}%';
    final preferHackMatches = filenameWithoutExt.toLowerCase().contains('hack');

    final likeResults = await db.rawQuery(
      '''
      SELECT g.game_id
      FROM app_ra_game_list g
      WHERE g.console_id = ($consoleSubquery)
        AND g.title LIKE ? 
      ORDER BY
        CASE
          WHEN ? = 1 AND g.title LIKE '~Hack~%' THEN 0
          WHEN ? = 1 THEN 1
          WHEN ? = 0 AND g.title LIKE '~Hack~%' THEN 1
          ELSE 0
        END,
        CASE WHEN g.title LIKE '%[Subset%' THEN 1 ELSE 0 END,
        LENGTH(g.title) ASC,
        g.title ASC
      LIMIT 1
      ''',
      [
        systemFolderName,
        searchPattern,
        preferHackMatches ? 1 : 0,
        preferHackMatches ? 1 : 0,
        preferHackMatches ? 1 : 0,
      ],
    );
    if (likeResults.isNotEmpty) {
      return int.tryParse(likeResults.first['game_id']?.toString() ?? '0') ?? 0;
    }

    return null;
  }

  static Future<OwnedWeekGameResolution?> findBestLocalGameByRaGameId(
    int raGameId,
  ) async {
    final db = await SqliteService.getDatabase();
    final results = await db.rawQuery(
      '''
      SELECT
        ur.*,
        s.folder_name AS system_folder_name,
        s.real_name AS system_real_name,
        s.short_name AS system_short_name
      FROM user_roms ur
      JOIN app_systems s ON ur.app_system_id = s.id
      WHERE ur.id_ra = ?
      ORDER BY
        CASE WHEN ur.last_played IS NULL THEN 1 ELSE 0 END ASC,
        ur.last_played DESC,
        ur.is_favorite DESC,
        LOWER(COALESCE(ur.title_name, ur.filename)) ASC
      LIMIT 1
      ''',
      [raGameId],
    );
    if (results.isEmpty) return null;

    final game = DatabaseGameModel.fromJson(
      Map<String, dynamic>.from(results.first),
    );
    return OwnedWeekGameResolution(raGameId: raGameId, game: game);
  }
}
