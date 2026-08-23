import '../data/datasources/sqlite_service.dart';
import 'package:neostation/services/logger_service.dart';

/// Every recorded mapping, resolvable without another query.
///
/// [RommSaveMapRepository.getRommRomId] is the single-game path and costs up to
/// two queries per call, one of which scans a whole system folder. A sweep over
/// the library asks the same question thousands of times, so it reads the table
/// once into this and looks up locally. Same matching rules as the single-game
/// path, kept in the repository so there is only one definition of them.
class RommRomIdIndex {
  final Map<String, int> _byKey;

  const RommRomIdIndex(this._byKey);

  /// Composite key for the two-part identity, built in exactly one place so
  /// that the read and the write cannot drift apart.
  ///
  /// The separator is a tab rather than a space because both halves can contain
  /// spaces: `("Game Boy", "Tetris")` and `("Game", "Boy Tetris")` would
  /// otherwise collide on one key.
  static String _keyFor(String systemFolder, String romname) =>
      '$systemFolder\t$romname';

  /// The RomM ROM id for a local game, or null when it isn't linked.
  int? lookup(String romname, String systemFolder) =>
      _byKey[_keyFor(systemFolder, romname)];

  /// Number of mapped games (not index entries — a game is indexed under both
  /// spellings of its name).
  int get mappedGames => _byKey.values.toSet().length;

  bool get isEmpty => _byKey.isEmpty;
}

/// Repository for the RomM save-sync mapping table (`app_romm_rom_map`).
///
/// Links a local game (its [romname] within a [systemFolder]) to the RomM ROM
/// id it was downloaded from, so save/state sync can target the correct
/// `rom_id`. Per the architecture rules, this is the only layer that touches
/// [SqliteService] for this data.
class RommSaveMapRepository {
  static final _log = LoggerService.instance;

  /// Records (or replaces) the mapping for a downloaded ROM.
  static Future<void> putMapping({
    required String romname,
    required String systemFolder,
    required int rommRomId,
    String? fsName,
  }) async {
    try {
      final db = await SqliteService.getDatabase();
      await db.insert('app_romm_rom_map', {
        'romname': romname,
        'system_folder': systemFolder,
        'romm_rom_id': rommRomId,
        'romm_fs_name': fsName,
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      _log.e('Error saving RomM rom map ($romname/$systemFolder): $e');
    }
  }

  /// Returns the on-disk indexed name (`romname`) recorded for [rommRomId]
  /// within [systemFolder], or null if that ROM hasn't been downloaded here.
  ///
  /// Used to recognise an already-downloaded multi-disc game whose bundled
  /// playlist kept an unpredictable basename we can't reconstruct from the
  /// ROM's fsName — the recorded name is the authoritative on-disk `.m3u`.
  static Future<String?> getIndexedNameForRomId(
    int rommRomId,
    String systemFolder,
  ) async {
    try {
      final db = await SqliteService.getDatabase();
      final rows = await db.query(
        'app_romm_rom_map',
        columns: ['romname'],
        where: 'romm_rom_id = ? AND system_folder = ?',
        whereArgs: [rommRomId, systemFolder],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final name = rows.first['romname']?.toString();
      return (name == null || name.isEmpty) ? null : name;
    } catch (e) {
      _log.e('Error reading RomM rom map for id $rommRomId: $e');
      return null;
    }
  }

  /// Returns the RomM ROM id for a local game, or null if not mapped.
  static Future<int?> getRommRomId(String romname, String systemFolder) async {
    try {
      final db = await SqliteService.getDatabase();
      final rows = await db.query(
        'app_romm_rom_map',
        columns: ['romm_rom_id'],
        where: 'romname = ? AND system_folder = ?',
        whereArgs: [romname, systemFolder],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return int.tryParse(rows.first['romm_rom_id'].toString());
      }
      return await _romIdByStem(db, romname, systemFolder);
    } catch (e) {
      _log.e('Error reading RomM rom map ($romname/$systemFolder): $e');
      return null;
    }
  }

  /// Reads the whole mapping table into a [RommRomIdIndex].
  ///
  /// For callers that resolve many games at once (the pending-upload sweep):
  /// one query instead of two per game. Each row is indexed under both the
  /// stored name and its extension-stripped form, for the same reason
  /// [_romIdByStem] exists — the table is written with the on-disk filename
  /// (`Game.zip`) while a `GameModel` carries it already stripped.
  ///
  /// Returns an empty index on error, which reads as "no games are linked" and
  /// makes the sweep a no-op rather than a crash.
  static Future<RommRomIdIndex> getRomIdIndex() async {
    try {
      final db = await SqliteService.getDatabase();
      final rows = await db.query(
        'app_romm_rom_map',
        columns: ['romname', 'system_folder', 'romm_rom_id'],
      );
      final index = <String, int>{};
      for (final row in rows) {
        final romId = int.tryParse(row['romm_rom_id'].toString());
        final stored = row['romname']?.toString() ?? '';
        final folder = row['system_folder']?.toString() ?? '';
        if (romId == null || stored.isEmpty || folder.isEmpty) continue;
        index[RommRomIdIndex._keyFor(folder, stored)] = romId;
        final stem = _stripExtension(stored);
        // Only ever *add* the stem spelling: an exact match must win, matching
        // the order the single-game path tries them in.
        index.putIfAbsent(RommRomIdIndex._keyFor(folder, stem), () => romId);
      }
      return RommRomIdIndex(index);
    } catch (e) {
      _log.e('Error reading the RomM rom map: $e');
      return const RommRomIdIndex({});
    }
  }

  /// Drops the mapping for a local game that no longer exists, returning the
  /// RomM id it was linked to (null when the game wasn't downloaded from RomM).
  ///
  /// Deleting a game locally has to unlink it, or the row outlives the file:
  /// save sync would keep targeting that `rom_id`, and a later scan of an
  /// unrelated game that happens to share the name would inherit the link.
  /// Resolution goes through [getRommRomId] so the extension-stripped callers
  /// (see [_romIdByStem]) unlink too, then deletes by id within the system —
  /// matching whichever spelling of the name the row was written with.
  static Future<int?> removeMapping(String romname, String systemFolder) async {
    try {
      final romId = await getRommRomId(romname, systemFolder);
      if (romId == null) return null;
      final db = await SqliteService.getDatabase();
      await db.delete(
        'app_romm_rom_map',
        where: 'romm_rom_id = ? AND system_folder = ?',
        whereArgs: [romId, systemFolder],
      );
      return romId;
    } catch (e) {
      _log.e('Error removing RomM rom map ($romname/$systemFolder): $e');
      return null;
    }
  }

  /// Resolves RomM ROM ids to the local `rom_path` of the game they're linked
  /// to, skipping ids that aren't linked here or whose row no longer has a
  /// matching game.
  ///
  /// For the connect-time playtime pull, which starts from a short list of ids
  /// the *server* named and has to get back to local rows. Deliberately not
  /// built on [getRomIdIndex] + the game list: that pair resolves every linked
  /// game in the library to answer a question about a handful of them, and this
  /// runs on connect whether or not RomM is the active save provider.
  ///
  /// Both spellings of the stored name are tried, for the reason [_romIdByStem]
  /// exists — the mapping is written with the on-disk filename (`Game.zip`)
  /// while `user_roms.filename` carries it stripped. Only the *stored* name is
  /// stripped, never the one read back, so a title with its own dot ("Mr. Do")
  /// can't be cut short.
  static Future<Map<int, String>> getRomPathsForRomIds(
    Iterable<int> romIds,
  ) async {
    final ids = romIds.toSet();
    if (ids.isEmpty) return const {};
    final out = <int, String>{};
    try {
      final db = await SqliteService.getDatabase();
      final placeholders = List.filled(ids.length, '?').join(',');
      final mapRows = await db.query(
        'app_romm_rom_map',
        columns: ['romname', 'system_folder', 'romm_rom_id'],
        where: 'romm_rom_id IN ($placeholders)',
        whereArgs: ids.toList(),
      );
      for (final row in mapRows) {
        final romId = int.tryParse(row['romm_rom_id'].toString());
        final stored = row['romname']?.toString() ?? '';
        final folder = row['system_folder']?.toString() ?? '';
        if (romId == null || stored.isEmpty || folder.isEmpty) continue;
        if (out.containsKey(romId)) continue;

        final games = await db.rawQuery(
          '''
          SELECT ur.rom_path
          FROM user_roms ur
          JOIN app_systems s ON ur.app_system_id = s.id
          WHERE s.folder_name = ? AND ur.filename IN (?, ?)
          LIMIT 1
          ''',
          [folder, stored, _stripExtension(stored)],
        );
        if (games.isEmpty) continue;
        final path = games.first['rom_path']?.toString() ?? '';
        if (path.isNotEmpty) out[romId] = path;
      }
    } catch (e) {
      // An empty result reads as "nothing to pull", which is the right
      // degradation for a statistic.
      _log.e('Error resolving RomM rom paths: $e');
    }
    return out;
  }

  /// Second pass for [getRommRomId], matching on the extension-stripped name.
  ///
  /// Callers disagree about what a "romname" is. The mapping is written with
  /// the on-disk filename (`Game.zip`) — and [getIndexedNameForRomId] depends
  /// on that staying intact — while a [GameModel] carries `romname` with the
  /// extension already stripped. An exact match therefore misses for every
  /// game launched normally, and since an unresolved id reads as "not a RomM
  /// game", save sync and playtime both went quietly nowhere.
  ///
  /// Scoped to one system folder, which the table's index covers, and only
  /// reached when the exact match fails.
  static Future<int?> _romIdByStem(
    dynamic db,
    String romname,
    String systemFolder,
  ) async {
    final rows = await db.query(
      'app_romm_rom_map',
      columns: ['romname', 'romm_rom_id'],
      where: 'system_folder = ?',
      whereArgs: [systemFolder],
    );
    // Only the stored name is stripped. [romname] arrives already extensionless
    // here (the exact match above covers callers that pass a full filename),
    // and stripping it again would cut a title at its own dot — "Mr. Do"
    // becoming "Mr", matching the wrong ROM or nothing at all.
    for (final row in rows) {
      final stored = row['romname']?.toString() ?? '';
      if (_stripExtension(stored) == romname) {
        return int.tryParse(row['romm_rom_id'].toString());
      }
    }
    return null;
  }

  /// Drops a trailing file extension, matching `DatabaseGameModel.romname`.
  static String _stripExtension(String name) {
    final lastDot = name.lastIndexOf('.');
    return lastDot > 0 ? name.substring(0, lastDot) : name;
  }
}
