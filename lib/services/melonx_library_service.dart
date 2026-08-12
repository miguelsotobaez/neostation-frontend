import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:external_folder_access/external_folder_access.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/main.dart' show rootNavigatorKey;
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/providers/sqlite_database_provider.dart';
import 'package:neostation/repositories/system_repository.dart';
import 'package:neostation/services/config_service.dart';
import 'package:neostation/services/ios_shortcut_jit_launch_service.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Integrates NeoStation with MeloNX iOS's alternate-frontend URL schemes.
///
/// Library export request:
///   melonx://gameInfo?scheme=neostation
///
/// MeloNX callback:
///   neostation://melonx?games=<base64url(JSON [GameScheme])>
///
/// A MeloNX GameScheme contains titleName, titleId, developer, version and
/// iconData. NeoStation imports the human-readable metadata and uses iconData
/// as local fallback artwork, while keeping the persistent SharedPreferences
/// cache lightweight by excluding the image bytes from it.
///
/// Exported games are imported directly into NeoStation's Nintendo Switch
/// catalogue. This does not depend on NeoStation being able to scan MeloNX's
/// ROM folder. Games without a matching physical NeoStation row are represented
/// by a virtual `melonx://game?...` rom_path and can therefore launch straight
/// back into MeloNX.
class MelonxLibraryService {
  MelonxLibraryService._();

  static final _log = LoggerService.instance;

  static const String _callbackScheme = 'neostation';
  static const String _callbackHost = 'melonx';
  static const String _prefsKey = 'melonx_library_cache_v1';
  static const String _virtualScheme = 'melonx';
  // MeloNX's compatibility scheme used by ManicEMU for frontend launches.
  // Keep NeoStation's stored virtual rows on melonx:// for backward
  // compatibility, but translate to this scheme only at launch time.
  static const String _frontendLaunchScheme = 'atariemulator';
  static const String _jitShortcutName =
      IosShortcutJitLaunchService.melonxShortcutName;

  /// Lookup keys (Title ID and title name, case-insensitive) -> lightweight
  /// MeloNX GameScheme metadata.
  static Map<String, Map<String, dynamic>>? _cache;

  /// True for NeoStation rows backed by MeloNX's direct-launch deeplink rather
  /// than a local filesystem path.
  static bool isVirtualLibraryPath(String romPath) {
    final uri = Uri.tryParse(romPath);
    if (uri == null || uri.scheme.toLowerCase() != _virtualScheme) {
      return false;
    }
    return uri.host.toLowerCase() == 'game';
  }

  /// Opens MeloNX and asks it to export the complete Nintendo Switch library.
  ///
  /// MeloNX returns asynchronously through `neostation://melonx?...`; the
  /// callback is handled by [handleIncomingUri].
  static Future<bool> requestLibrarySync() async {
    // IMPORTANT: do not pass this request through Dart Uri on iOS. Dart
    // normalizes URI hosts to lowercase, turning `gameInfo` into `gameinfo`.
    // MeloNX currently switches on the camel-cased host `gameInfo`, so that
    // normalization opens MeloNX but silently misses the export handler.
    const rawUrl = 'melonx://gameInfo?scheme=$_callbackScheme';

    await _writeDebugFile(
      'melonx_sync_debug.txt',
      'STATE: REQUESTED\n'
          'Request URL (raw): $rawUrl\n'
          'IMPORTANT: host must remain gameInfo (capital I).\n'
          'Callback expected: neostation://melonx?games=<base64url>\n\n'
          'If this file still says REQUESTED after returning to NeoStation, '
          'MeloNX did not send the library callback.',
    );

    try {
      final bool opened;
      if (Platform.isIOS) {
        opened = await ExternalFolderAccess.openRawUrl(rawUrl) ?? false;
      } else {
        opened = await launchUrl(
          Uri.parse(rawUrl),
          mode: LaunchMode.externalApplication,
        );
      }
      if (!opened) {
        await _appendDebugFile(
          'melonx_sync_debug.txt',
          '\nURL open returned false: MeloNX could not be opened.',
        );
      }
      return opened;
    } catch (e) {
      _log.e('MelonxLibraryService: failed to request library sync: $e');
      await _appendDebugFile(
        'melonx_sync_debug.txt',
        '\nERROR opening MeloNX: $e',
      );
      return false;
    }
  }

  /// Handles MeloNX's `neostation://melonx?games=...` callback.
  /// Returns true only when the URI belongs to MeloNX and was parsed/imported.
  static Future<bool> handleIncomingUri(Uri uri) async {
    if (uri.scheme.toLowerCase() != _callbackScheme ||
        uri.host.toLowerCase() != _callbackHost) {
      return false;
    }

    await _writeDebugFile(
      'melonx_sync_debug.txt',
      'STATE: CALLBACK_RECEIVED\nURI host: ${uri.host}\n'
          'Has games parameter: ${uri.queryParameters.containsKey('games')}',
    );

    final gamesParam = uri.queryParameters['games'];
    if (gamesParam == null || gamesParam.isEmpty) {
      _log.w('MelonxLibraryService: callback with no "games" param');
      await _appendDebugFile(
        'melonx_sync_debug.txt',
        '\nERROR: callback contained no games parameter.',
      );
      return false;
    }

    try {
      final normalized = base64Url.normalize(gamesParam);
      final jsonBytes = base64Url.decode(normalized);
      final decoded = jsonDecode(utf8.decode(jsonBytes));

      if (decoded is! List) {
        _log.e('MelonxLibraryService: decoded payload is not a JSON array');
        await _appendDebugFile(
          'melonx_sync_debug.txt',
          '\nERROR: decoded games payload is not a JSON array.',
        );
        return false;
      }

      final games = <Map<String, dynamic>>[];
      final lookup = <String, Map<String, dynamic>>{};

      for (final entry in decoded) {
        if (entry is! Map) continue;
        final raw = Map<String, dynamic>.from(entry);

        final titleName = raw['titleName']?.toString().trim() ?? '';
        final titleId = raw['titleId']?.toString().trim() ?? '';
        if (titleName.isEmpty && titleId.isEmpty) continue;

        // iconData can be sizeable. Keep it only for this sync so NeoStation
        // can import MeloNX's artwork, then strip it from the persistent cache.
        final game = <String, dynamic>{
          if (raw['id'] != null) 'id': raw['id'].toString(),
          'titleName': titleName,
          'titleId': titleId,
          'developer': raw['developer']?.toString() ?? '',
          'version': raw['version']?.toString() ?? '',
          if (raw['iconData'] != null) 'iconData': raw['iconData'],
        };
        game['launchURL'] = _launchUriForGame(game).toString();

        games.add(game);

        // Keep the cache tiny. MeloNX's iconData can be a large base64 image
        // for every game; it is consumed during import and written to NeoStation's
        // media folder instead of being duplicated in SharedPreferences.
        final cacheGame = Map<String, dynamic>.from(game)..remove('iconData');
        _index(lookup, titleId, cacheGame);
        _index(lookup, titleName, cacheGame);
      }

      _cache = lookup;
      await _persist(lookup);

      final importResult = await _importIntoNeoStation(games);

      _log.i(
        'MelonxLibraryService: synced ${games.length} Switch games; '
        '${importResult.virtualRows} virtual rows, '
        '${importResult.physicalRows} existing physical rows',
      );

      final debugGames = games.map((game) {
        final copy = Map<String, dynamic>.from(game)..remove('iconData');
        return copy;
      }).toList();

      await _writeDebugFile(
        'melonx_sync_debug.txt',
        'STATE: IMPORTED\n'
            'MeloNX games: ${games.length}\n'
            'NeoStation virtual Switch rows: ${importResult.virtualRows}\n'
            'Existing physical Switch rows reused: ${importResult.physicalRows}\n'
            'MeloNX artwork files imported: ${importResult.artworkRows}\n'
            'Stale MeloNX rows removed: ${importResult.removedRows}\n'
            'Switch rows now in NeoStation: ${importResult.totalSwitchRows}\n\n'
            'Imported metadata (iconData omitted from this debug file):\n'
            '${const JsonEncoder.withIndent('  ').convert(debugGames)}',
      );

      await _refreshNeoStationUi();
      return true;
    } catch (e, stack) {
      _log.e('MelonxLibraryService: failed to parse/import callback: $e');
      await _writeDebugFile(
        'melonx_sync_debug.txt',
        'STATE: ERROR\n'
            'Failed to parse/import MeloNX callback.\n'
            'Error: $e\n'
            'Stack: $stack',
      );
      return false;
    }
  }

  /// Imports the exported MeloNX library directly into NeoStation's Nintendo
  /// Switch catalogue.
  ///
  /// If a physical Switch row already has the same Title ID (or, as a fallback,
  /// the same title name), that row is reused and enriched. Otherwise a virtual
  /// `melonx://game?...` row is created. A normal ROM-folder rescan therefore
  /// isn't required for MeloNX-only games to appear in the main Switch library.
  static Future<({
    int virtualRows,
    int physicalRows,
    int artworkRows,
    int removedRows,
    int totalSwitchRows,
  })> _importIntoNeoStation(List<Map<String, dynamic>> games) async {
    final switchSystem = await SystemRepository.getSystemByFolderName('switch');
    if (switchSystem?.id == null) {
      throw StateError('NeoStation Nintendo Switch system definition was not found');
    }

    final systemId = switchSystem!.id!;
    final db = await SqliteService.getDatabase();
    final existingRows = await db.rawQuery(
      'SELECT filename, rom_path, title_id, title_name '
      'FROM user_roms WHERE app_system_id = ?',
      [systemId],
    );

    final physicalByTitleId = <String, Map<String, Object?>>{};
    final physicalByTitleName = <String, Map<String, Object?>>{};
    for (final row in existingRows) {
      final romPath = row['rom_path']?.toString() ?? '';
      if (isVirtualLibraryPath(romPath)) continue;

      final titleId = row['title_id']?.toString().trim() ?? '';
      final titleName = row['title_name']?.toString().trim() ?? '';
      if (titleId.isNotEmpty) {
        physicalByTitleId[titleId.toLowerCase()] = row;
      }
      if (titleName.isNotEmpty) {
        physicalByTitleName[titleName.toLowerCase()] = row;
      }
    }

    final desiredVirtualPaths = <String>{};
    final artworkWrites = <({String filename, Object? iconData})>[];
    var virtualRows = 0;
    var physicalRows = 0;

    await db.transaction((txn) async {
      for (final game in games) {
        final titleName = game['titleName']?.toString().trim() ?? '';
        final titleId = game['titleId']?.toString().trim() ?? '';
        final developer = game['developer']?.toString().trim() ?? '';
        final iconData = game['iconData'];
        if (titleName.isEmpty && titleId.isEmpty) continue;

        Map<String, Object?>? physical;
        if (titleId.isNotEmpty) {
          physical = physicalByTitleId[titleId.toLowerCase()];
        }
        if (physical == null && titleName.isNotEmpty) {
          physical = physicalByTitleName[titleName.toLowerCase()];
        }

        if (physical != null) {
          final physicalPath = physical['rom_path']?.toString();
          if (physicalPath != null && physicalPath.isNotEmpty) {
            await txn.rawUpdate(
              '''
              UPDATE user_roms SET
                title_id = CASE
                  WHEN title_id IS NULL OR title_id = '' THEN ? ELSE title_id END,
                title_name = CASE
                  WHEN title_name IS NULL OR title_name = '' THEN ? ELSE title_name END,
                developer = CASE
                  WHEN developer IS NULL OR developer = '' THEN ? ELSE developer END,
                updated_at = datetime('now')
              WHERE rom_path = ?
              ''',
              [titleId, titleName, developer, physicalPath],
            );
          }
          physicalRows++;
          continue;
        }

        final launchUri = _launchUriForGame(game);
        final virtualPath = launchUri.toString();
        desiredVirtualPaths.add(virtualPath);

        // MeloNX's exported GameScheme does not contain the original ROM file
        // name. Use a stable synthetic filename; title_name remains the value
        // displayed by NeoStation.
        final syntheticFilename = titleId.isNotEmpty
            ? '$titleId.melonx'
            : '${_safeSyntheticName(titleName)}.melonx';

        await txn.rawInsert(
          '''
          INSERT INTO user_roms
            (app_system_id, app_emulator_unique_id, app_emulator_os_id,
             filename, rom_path, title_id, title_name, developer,
             created_at, updated_at)
          VALUES (?, NULL, NULL, ?, ?, ?, ?, ?, datetime('now'), datetime('now'))
          ON CONFLICT(rom_path) DO UPDATE SET
            app_system_id = excluded.app_system_id,
            filename = excluded.filename,
            title_id = CASE
              WHEN user_roms.title_id IS NULL OR user_roms.title_id = ''
              THEN excluded.title_id ELSE user_roms.title_id END,
            title_name = CASE
              WHEN user_roms.title_name IS NULL OR user_roms.title_name = ''
              THEN excluded.title_name ELSE user_roms.title_name END,
            developer = CASE
              WHEN user_roms.developer IS NULL OR user_roms.developer = ''
              THEN excluded.developer ELSE user_roms.developer END,
            updated_at = datetime('now')
          ''',
          [
            systemId,
            syntheticFilename,
            virtualPath,
            titleId,
            titleName,
            developer,
          ],
        );

        if (iconData != null) {
          artworkWrites.add((filename: syntheticFilename, iconData: iconData));
        }
        virtualRows++;
      }
    });

    // A fresh MeloNX export is authoritative only for MeloNX virtual rows.
    // Remove stale virtual entries while preserving every physical Switch ROM
    // and its user metadata.
    final virtualRowsInDb = await db.rawQuery(
      "SELECT rom_path FROM user_roms WHERE app_system_id = ? AND rom_path LIKE 'melonx://%'",
      [systemId],
    );
    final staleVirtualPaths = virtualRowsInDb
        .map((row) => row['rom_path']?.toString() ?? '')
        .where(
          (romPath) =>
              romPath.isNotEmpty && !desiredVirtualPaths.contains(romPath),
        )
        .toList();

    var removedRows = 0;
    if (staleVirtualPaths.isNotEmpty) {
      await db.transaction((txn) async {
        const batchSize = 100;
        for (var i = 0; i < staleVirtualPaths.length; i += batchSize) {
          final end = (i + batchSize < staleVirtualPaths.length)
              ? i + batchSize
              : staleVirtualPaths.length;
          final batch = staleVirtualPaths.sublist(i, end);
          final placeholders = List.filled(batch.length, '?').join(',');
          removedRows += await txn.rawDelete(
            'DELETE FROM user_roms WHERE app_system_id = ? '
            'AND rom_path IN ($placeholders)',
            [systemId, ...batch],
          );
        }
      });
    }

    final artworkRows = await _writeMeloNxArtwork(artworkWrites);

    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM user_roms WHERE app_system_id = ?',
      [systemId],
    );
    final totalSwitchRows =
        int.tryParse('${countRows.first['count'] ?? 0}') ?? 0;

    if (totalSwitchRows > 0) {
      await SystemRepository.addDetectedSystem(systemId, 'switch');
    } else {
      await SystemRepository.removeDetectedSystem(systemId);
    }

    return (
      virtualRows: virtualRows,
      physicalRows: physicalRows,
      artworkRows: artworkRows,
      removedRows: removedRows,
      totalSwitchRows: totalSwitchRows,
    );
  }

  /// Decodes MeloNX's exported iconData and writes it as fallback local artwork.
  /// Existing NeoStation/ScreenScraper art is preserved. When the user later
  /// scrapes a MeloNX virtual title, the scraper can replace this fallback.
  static Future<int> _writeMeloNxArtwork(
    List<({String filename, Object? iconData})> items,
  ) async {
    if (items.isEmpty) return 0;

    final mediaRoot = await ConfigService.getMediaPath();
    final mediaDirs = <Directory>[
      Directory(path.join(mediaRoot, 'switch', 'box2d')),
      Directory(path.join(mediaRoot, 'switch', 'screenshots')),
    ];
    for (final dir in mediaDirs) {
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
    }

    var written = 0;
    for (final item in items) {
      final bytes = _decodeIconData(item.iconData);
      if (bytes == null || bytes.isEmpty) continue;

      final mediaKey = FileProvider.stripRomExtension(item.filename);
      final extension = _detectImageExtension(bytes);

      for (final dir in mediaDirs) {
        final pngFile = File(path.join(dir.path, '$mediaKey.png'));
        final jpgFile = File(path.join(dir.path, '$mediaKey.jpg'));
        final jpegFile = File(path.join(dir.path, '$mediaKey.jpeg'));

        if (await pngFile.exists() ||
            await jpgFile.exists() ||
            await jpegFile.exists()) {
          continue;
        }

        final target = File(path.join(dir.path, '$mediaKey.$extension'));
        await target.writeAsBytes(bytes, flush: true);
        written++;
      }
    }
    return written;
  }

  static List<int>? _decodeIconData(Object? value) {
    if (value == null) return null;

    if (value is List) {
      try {
        return value.map((e) => int.parse(e.toString())).toList();
      } catch (_) {
        return null;
      }
    }

    if (value is! String || value.trim().isEmpty) return null;
    var text = value.trim();
    final comma = text.indexOf(',');
    if (text.startsWith('data:') && comma >= 0) {
      text = text.substring(comma + 1);
    }

    try {
      return base64Decode(text);
    } catch (_) {
      try {
        return base64Url.decode(base64Url.normalize(text));
      } catch (_) {
        return null;
      }
    }
  }

  static String _detectImageExtension(List<int> bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    return 'jpg';
  }

  static Future<void> _refreshNeoStationUi() async {
    try {
      final context = rootNavigatorKey.currentContext;
      if (context == null) return;

      await Provider.of<SqliteDatabaseProvider>(
        context,
        listen: false,
      ).loadGamesForSystem('switch');
      await Provider.of<SqliteConfigProvider>(
        context,
        listen: false,
      ).refreshDetectedSystems();
    } catch (e) {
      _log.e('MelonxLibraryService: UI refresh failed: $e');
    }
  }

  static Uri _launchUriForGame(Map<String, dynamic> game) {
    final titleId = game['titleId']?.toString().trim() ?? '';
    final titleName = game['titleName']?.toString().trim() ?? '';

    if (titleId.isNotEmpty) {
      return Uri(
        scheme: _virtualScheme,
        host: 'game',
        queryParameters: {'id': titleId},
      );
    }

    return Uri(
      scheme: _virtualScheme,
      host: 'game',
      queryParameters: {'name': titleName},
    );
  }

  static String _safeSyntheticName(String value) {
    final cleaned = value
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'MeloNX Game' : cleaned;
  }

  static void _index(
    Map<String, Map<String, dynamic>> target,
    String key,
    Map<String, dynamic> entry,
  ) {
    if (key.isEmpty) return;
    target[key] = entry;
    target[key.toLowerCase()] = entry;
  }

  /// Loads the last MeloNX export metadata from SharedPreferences at startup.
  static Future<void> loadCachedLibrary() async {
    if (_cache != null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) {
        _cache = {};
        return;
      }

      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        _cache = decoded.map(
          (key, value) => MapEntry(
            key.toString(),
            Map<String, dynamic>.from(value as Map),
          ),
        );
      } else {
        _cache = {};
      }
    } catch (e) {
      _log.e('MelonxLibraryService: failed loading cached library: $e');
      _cache = {};
    }
  }

  static Future<void> _persist(Map<String, Map<String, dynamic>> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (e) {
      _log.e('MelonxLibraryService: failed persisting library cache: $e');
    }
  }

  /// Whether a non-empty MeloNX library has been received at least once.
  static bool get hasSyncedLibrary => (_cache?.isNotEmpty ?? false);

  /// Launches a Nintendo Switch title in MeloNX.
  ///
  /// Virtual rows already contain the exact `melonx://game?...` URL. For a
  /// physical Switch row, [titleId] / [titleName] are matched against the last
  /// synced MeloNX export so NeoStation can still prefer MeloNX without
  /// creating a duplicate library entry.
  static Future<bool> launchGameByRomPath(
    String romPath, {
    String? titleId,
    String? titleName,
  }) async {
    if (isVirtualLibraryPath(romPath)) {
      try {
        final storedUri = Uri.parse(romPath);
        final rawLaunchUrl = _frontendLaunchUrlFromUri(storedUri);
        await _writeDebugFile(
          'melonx_launch_debug.txt',
          'Virtual MeloNX library row.\n'
              'Strategy: StikDebug universal.js preflight, then single MeloNX game open.\n'
              'Stored NeoStation URL: $storedUri\n'
              'Opened URL: $rawLaunchUrl',
        );
        return await _openFrontendLaunchUrl(rawLaunchUrl);
      } catch (e) {
        _log.e('MelonxLibraryService: virtual launch failed: $e');
        return false;
      }
    }

    final cache = _cache;
    if (cache == null || cache.isEmpty) {
      await _writeDebugFile(
        'melonx_launch_debug.txt',
        'romPath: $romPath\ncache is null or empty (sync MeloNX first)',
      );
      return false;
    }

    final normalizedTitleId = titleId?.trim() ?? '';
    final normalizedTitleName = titleName?.trim() ?? '';
    final entry =
        (normalizedTitleId.isNotEmpty
            ? cache[normalizedTitleId] ?? cache[normalizedTitleId.toLowerCase()]
            : null) ??
        (normalizedTitleName.isNotEmpty
            ? cache[normalizedTitleName] ??
                cache[normalizedTitleName.toLowerCase()]
            : null);

    await _writeDebugFile(
      'melonx_launch_debug.txt',
      'romPath: $romPath\n'
          'titleId: $normalizedTitleId\n'
          'titleName: $normalizedTitleName\n'
          'match found: ${entry != null}\n'
          'matched entry: ${entry != null ? jsonEncode(entry) : 'none'}',
    );

    if (entry == null) return false;

    final launchUrlString = entry['launchURL']?.toString();
    final storedUri = launchUrlString == null || launchUrlString.isEmpty
        ? _launchUriForGame(entry)
        : Uri.parse(launchUrlString);
    final rawLaunchUrl = _frontendLaunchUrlFromUri(storedUri);

    try {
      await _appendDebugFile(
        'melonx_launch_debug.txt',
        '\nStrategy: StikDebug universal.js preflight, then single MeloNX game open.\n'
            'Stored NeoStation URL: $storedUri\n'
            'Opened URL: $rawLaunchUrl',
      );
      return await _openFrontendLaunchUrl(rawLaunchUrl);
    } catch (e) {
      _log.e('MelonxLibraryService: failed to launch $rawLaunchUrl: $e');
      return false;
    }
  }

  /// Converts NeoStation's persistent `melonx://game?...` virtual URL into
  /// MeloNX's compatibility frontend scheme. ManicEMU uses this exact scheme
  /// and performs one native UIApplication.open call, without a JIT delay or
  /// duplicate game launch request.
  static String _frontendLaunchUrlFromUri(Uri uri) {
    final id = uri.queryParameters['id']?.trim() ?? '';
    if (id.isNotEmpty) {
      return '$_frontendLaunchScheme://game?id=${Uri.encodeQueryComponent(id)}';
    }

    final name = uri.queryParameters['name']?.trim() ?? '';
    if (name.isNotEmpty) {
      return '$_frontendLaunchScheme://game?name=${Uri.encodeQueryComponent(name)}';
    }

    throw StateError('MeloNX launch URL has neither id nor name: $uri');
  }

  /// On iOS, hand the complete sequence to Apple Shortcuts instead of trying
  /// to open the game from NeoStation while NeoStation is suspended in the
  /// background. The shortcut receives [rawUrl] as its Shortcut Input, runs
  /// StikDebug's official "Enable JIT" action for MeloNX, then opens that input.
  ///
  /// This keeps NeoStation, MeloNX and StikDebug unmodified and lets the app that
  /// owns the foreground workflow (Shortcuts) perform the final game deeplink.
  static Future<bool> _openFrontendLaunchUrl(String rawUrl) async {
    final launchUri = Uri.parse(rawUrl);

    if (Platform.isIOS) {
      await _writeDebugFile(
        'melonx_shortcut_launch_debug.txt',
        'STATE: SHORTCUT_REQUESTED\n'
            'Shortcut: $_jitShortcutName\n'
            'Game URL: $rawUrl\n'
            'Expected shortcut flow: StikDebug Enable JIT -> Wait -> Open Shortcut Input',
      );

      final opened = await IosShortcutJitLaunchService.run(
        shortcutName: _jitShortcutName,
        input: launchUri.toString(),
      );

      if (!opened) {
        await _appendDebugFile(
          'melonx_shortcut_launch_debug.txt',
          '\nSTATE: SHORTCUT_OPEN_FAILED',
        );
      }
      return opened;
    }

    return launchUrl(launchUri, mode: LaunchMode.externalApplication);
  }

  /// Device-readable diagnostics for CI-only iOS development where an Xcode
  /// console is not available.
  static Future<void> _writeDebugFile(String name, String content) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final file = File(path.join(docsDir.path, name));
      await file.writeAsString('--- ${DateTime.now()} ---\n$content');
    } catch (e) {
      _log.e('MelonxLibraryService: failed writing debug file $name: $e');
    }
  }

  static Future<void> _appendDebugFile(String name, String content) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final file = File(path.join(docsDir.path, name));
      await file.writeAsString(content, mode: FileMode.append);
    } catch (e) {
      _log.e('MelonxLibraryService: failed appending debug file $name: $e');
    }
  }
}
