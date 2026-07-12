import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:xml/xml.dart';

import '../data/datasources/sqlite_service.dart';
import '../repositories/scraper_repository.dart';
import 'logger_service.dart';

/// Summary of an ES-DE import run, surfaced to the settings UI.
class EsdeImportResult {
  /// Number of ES-DE system folders matched to a NeoStation system.
  final int systemsMatched;

  /// Number of ES-DE system folders that could not be mapped and were skipped.
  final int systemsUnmatched;

  /// Number of `<game>` entries whose metadata was created or filled.
  final int gamesImported;

  /// Number of `<game>` entries with no matching scanned ROM (skipped).
  final int gamesUnmatched;

  /// Number of games whose favorite / last-played flags were updated.
  final int statsUpdated;

  const EsdeImportResult({
    this.systemsMatched = 0,
    this.systemsUnmatched = 0,
    this.gamesImported = 0,
    this.gamesUnmatched = 0,
    this.statsUpdated = 0,
  });

  EsdeImportResult _add({
    int systemsMatched = 0,
    int systemsUnmatched = 0,
    int gamesImported = 0,
    int gamesUnmatched = 0,
    int statsUpdated = 0,
  }) {
    return EsdeImportResult(
      systemsMatched: this.systemsMatched + systemsMatched,
      systemsUnmatched: this.systemsUnmatched + systemsUnmatched,
      gamesImported: this.gamesImported + gamesImported,
      gamesUnmatched: this.gamesUnmatched + gamesUnmatched,
      statsUpdated: this.statsUpdated + statsUpdated,
    );
  }
}

/// Imports metadata and wires up fallback artwork from an ES-DE
/// (EmulationStation Desktop Edition) installation.
///
/// Metadata is parsed from `gamelists/<system>/gamelist.xml` and merged into
/// NeoStation's `user_screenscraper_metadata` on a fill-gaps-only basis (never
/// clobbering existing NeoStation-scraped values). Artwork is NOT copied: the
/// ES-DE folder path plus a per-system `esde_media_dir` are persisted so
/// [FileProvider] can resolve `downloaded_media/` files as read-time fallback
/// (a later NeoStation scrape lands in NeoStation's own media folder and takes
/// precedence automatically).
class EsdeImportService {
  static final _log = LoggerService.instance;

  /// NeoStation media-type folder -> ES-DE `downloaded_media` category.
  /// (Reference for the read-time fallback in FileProvider; kept here so the
  /// mapping lives with the rest of the ES-DE knowledge.)
  static const Map<String, String> mediaTypeToEsdeCategory = {
    'box2d': 'covers',
    'wheels': 'marquees',
    'screenshots': 'screenshots',
    'fanarts': 'fanart',
    'videos': 'videos',
  };

  /// Runs the import against [esdeRoot] (the ES-DE application folder that
  /// contains `gamelists/` and `downloaded_media/`).
  ///
  /// [onProgress] is invoked as `(fraction 0..1, currentSystemLabel)`.
  static Future<EsdeImportResult> import(
    String esdeRoot, {
    void Function(double progress, String label)? onProgress,
  }) async {
    var result = const EsdeImportResult();

    final gamelistsDir = Directory(path.join(esdeRoot, 'gamelists'));
    if (!gamelistsDir.existsSync()) {
      _log.w('ES-DE import: no gamelists/ dir at $esdeRoot');
      return result;
    }

    final systemDirs = gamelistsDir
        .listSync()
        .whereType<Directory>()
        .where((d) => File(path.join(d.path, 'gamelist.xml')).existsSync())
        .toList();

    final preferredLang = await ScraperRepository.getPreferredLanguage();
    final descColumn = _descriptionColumn(preferredLang);

    for (var i = 0; i < systemDirs.length; i++) {
      final systemDir = systemDirs[i];
      final esdeDirName = path.basename(systemDir.path);
      onProgress?.call(i / systemDirs.length, esdeDirName);

      final system = await ScraperRepository.resolveSystemByFolderName(
        esdeDirName,
      );
      if (system == null) {
        _log.i(
          'ES-DE import: no NeoStation system for "$esdeDirName", skipping',
        );
        result = result._add(systemsUnmatched: 1);
        continue;
      }

      final appSystemId = system['app_system_id']!;
      result = result._add(systemsMatched: 1);

      result = await _importSystem(
        esdeRoot: esdeRoot,
        esdeDirName: esdeDirName,
        appSystemId: appSystemId,
        gamelistFile: File(path.join(systemDir.path, 'gamelist.xml')),
        descColumn: descColumn,
        accumulator: result,
      );

      await _recordEsdeMediaDir(esdeRoot, esdeDirName, appSystemId);
    }

    onProgress?.call(1.0, '');
    return result;
  }

  /// Clears all ES-DE-imported data so the import can be re-run from scratch.
  /// Deletes fill-gaps metadata rows (`is_fully_scraped = 0`, i.e. rows never
  /// upgraded by a NeoStation scrape) and clears every system's
  /// `esde_media_dir` so the read-time media fallback stops. The picked ES-DE
  /// folder path is kept so the import can be re-run with one tap;
  /// favorites / last-played are left untouched (indistinguishable from the
  /// user's own). Returns the number of metadata rows removed.
  static Future<int> reset() async {
    final db = await SqliteService.getDatabase();
    final deleted = await db.delete(
      'user_screenscraper_metadata',
      where: 'is_fully_scraped = 0',
    );
    await db.update(
      'user_system_settings',
      {'esde_media_dir': null},
      where: 'esde_media_dir IS NOT NULL',
    );
    _log.i('ES-DE reset: cleared $deleted metadata rows and media dirs');
    return deleted;
  }

  static Future<EsdeImportResult> _importSystem({
    required String esdeRoot,
    required String esdeDirName,
    required String appSystemId,
    required File gamelistFile,
    required String descColumn,
    required EsdeImportResult accumulator,
  }) async {
    var result = accumulator;
    XmlDocument doc;
    try {
      doc = XmlDocument.parse(await gamelistFile.readAsString());
    } catch (e) {
      _log.e('ES-DE import: failed to parse ${gamelistFile.path}: $e');
      return result;
    }

    final db = await SqliteService.getDatabase();

    for (final game in doc.findAllElements('game')) {
      final rawPath = _text(game, 'path');
      if (rawPath == null || rawPath.isEmpty) continue;
      final normalizedPath = rawPath.replaceAll('\\', '/');
      final filename = path.basename(normalizedPath);
      // ES-DE mirrors the ROM's subfolder (relative to the system's ROM dir)
      // inside downloaded_media, e.g. `<sys>/covers/<subdir>/<base>.png`. Capture
      // that subdir (empty when the ROM sits directly in the system folder) so
      // the read-time fallback can find nested artwork.
      final mediaSubdir = _mediaSubdir(normalizedPath);

      // Only import for ROMs NeoStation has already scanned.
      final rom = await db.query(
        'user_roms',
        columns: ['is_favorite', 'last_played'],
        where: 'app_system_id = ? AND filename = ? COLLATE NOCASE',
        whereArgs: [appSystemId, filename],
        limit: 1,
      );
      if (rom.isEmpty) {
        result = result._add(gamesUnmatched: 1);
        continue;
      }

      // --- Metadata (fill-gaps merge into user_screenscraper_metadata) ---
      final esdeMeta = <String, dynamic>{
        'real_name': _text(game, 'name'),
        descColumn: _text(game, 'desc'),
        'developer': _text(game, 'developer'),
        'publisher': _text(game, 'publisher'),
        'genre': _text(game, 'genre'),
        'players': _text(game, 'players'),
        'rating': _parseRating(_text(game, 'rating')),
        'release_date': _parseEsdeDateTime(
          _text(game, 'releasedate'),
        )?.toIso8601String(),
      };
      final wroteMeta = await ScraperRepository.mergeEsdeMetadata(
        appSystemId,
        filename,
        esdeMeta,
        mediaSubdir: mediaSubdir,
      );
      if (wroteMeta) result = result._add(gamesImported: 1);

      // --- Favorites / last-played (fill-gaps into user_roms) ---
      final favorite = _text(game, 'favorite')?.toLowerCase() == 'true';
      final lastPlayed = _parseEsdeDateTime(_text(game, 'lastplayed'));
      final update = <String, dynamic>{};

      final currentlyFavorite = (rom.first['is_favorite'] as int? ?? 0) == 1;
      if (favorite && !currentlyFavorite) update['is_favorite'] = 1;

      final curLastPlayed = rom.first['last_played'];
      final lastPlayedEmpty =
          curLastPlayed == null ||
          (curLastPlayed is String && curLastPlayed.trim().isEmpty) ||
          (curLastPlayed is num && curLastPlayed == 0);
      if (lastPlayed != null && lastPlayedEmpty) {
        update['last_played'] = lastPlayed.toIso8601String();
      }

      if (update.isNotEmpty) {
        await db.update(
          'user_roms',
          update,
          where: 'app_system_id = ? AND filename = ? COLLATE NOCASE',
          whereArgs: [appSystemId, filename],
        );
        result = result._add(statsUpdated: 1);
      }
    }

    return result;
  }

  /// Persists which ES-DE `downloaded_media` subfolder backs a NeoStation
  /// system so read-time fallback can resolve artwork. Prefers a folder that
  /// actually contains a `downloaded_media/<dir>` tree; otherwise only sets it
  /// when not already populated.
  static Future<void> _recordEsdeMediaDir(
    String esdeRoot,
    String esdeDirName,
    String appSystemId,
  ) async {
    final db = await SqliteService.getDatabase();
    final hasMedia = Directory(
      path.join(esdeRoot, 'downloaded_media', esdeDirName),
    ).existsSync();

    final existing = await db.query(
      'user_system_settings',
      columns: ['app_system_id', 'esde_media_dir'],
      where: 'app_system_id = ?',
      whereArgs: [appSystemId],
      limit: 1,
    );

    if (existing.isEmpty) {
      await db.insert('user_system_settings', {
        'app_system_id': appSystemId,
        'esde_media_dir': esdeDirName,
      });
      return;
    }

    final current = existing.first['esde_media_dir'];
    final currentEmpty =
        current == null || (current is String && current.trim().isEmpty);
    if (hasMedia || currentEmpty) {
      await db.update(
        'user_system_settings',
        {'esde_media_dir': esdeDirName},
        where: 'app_system_id = ?',
        whereArgs: [appSystemId],
      );
    }
  }

  /// Maps a preferred language code to a `user_screenscraper_metadata`
  /// description column, defaulting to English when unsupported.
  static String _descriptionColumn(String lang) {
    const supported = {'en', 'es', 'fr', 'de', 'it', 'pt'};
    final code = lang.toLowerCase();
    return supported.contains(code) ? 'description_$code' : 'description_en';
  }

  /// ES-DE stores rating as a 0..1 float string; NeoStation stores it on
  /// ScreenScraper's 0..20 scale (displayed as `rating / 2` out of 10), so
  /// scale the ES-DE value up by 20.
  static double? _parseRating(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final v = double.tryParse(raw.trim());
    if (v == null) return null;
    return v.clamp(0.0, 1.0) * 20.0;
  }

  /// Parses ES-DE's basic ISO datetime (`yyyyMMddTHHmmss`, e.g.
  /// `19950311T000000`) into a [DateTime]. Returns null on failure or
  /// placeholder/zero dates.
  static DateTime? _parseEsdeDateTime(String? raw) {
    if (raw == null) return null;
    final s = raw.trim();
    if (s.length < 8) return null;
    try {
      final year = int.parse(s.substring(0, 4));
      final month = int.parse(s.substring(4, 6));
      final day = int.parse(s.substring(6, 8));
      if (year <= 1 || month < 1 || month > 12 || day < 1 || day > 31) {
        return null;
      }
      var hour = 0, minute = 0, second = 0;
      if (s.length >= 15 && s[8] == 'T') {
        hour = int.parse(s.substring(9, 11));
        minute = int.parse(s.substring(11, 13));
        second = int.parse(s.substring(13, 15));
      }
      return DateTime(year, month, day, hour, minute, second);
    } catch (_) {
      return null;
    }
  }

  /// Extracts the ES-DE media subfolder from a gamelist `<path>` — the ROM's
  /// directory relative to the system folder, with a leading `./` stripped.
  /// Returns `''` when the ROM sits directly in the system folder.
  static String _mediaSubdir(String normalizedPath) {
    var p = normalizedPath;
    while (p.startsWith('./')) {
      p = p.substring(2);
    }
    final dir = path.dirname(p);
    if (dir == '.' || dir == '/' || dir.isEmpty) return '';
    return dir.startsWith('/') ? dir.substring(1) : dir;
  }

  static String? _text(XmlElement parent, String tag) {
    final el = parent.getElement(tag);
    if (el == null) return null;
    final t = el.innerText.trim();
    return t.isEmpty ? null : t;
  }
}
