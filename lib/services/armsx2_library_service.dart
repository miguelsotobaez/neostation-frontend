import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/main.dart' show rootNavigatorKey;
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/providers/sqlite_database_provider.dart';
import 'package:neostation/repositories/system_repository.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/services/ios_shortcut_jit_launch_service.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Integrates NeoStation with ARMSX2 iOS's URL-scheme library export and
/// direct-launch protocol.
///
/// ARMSX2 accepts:
///   armsx2://library?callback=neostation://armsx2
///
/// It calls NeoStation back with:
///   neostation://armsx2?source=armsx2-ios&payload=<base64url>
///
/// Unlike the normal NeoStation filesystem scanner, this service does not
/// require ARMSX2 games to live inside a `ps2/` subfolder. ARMSX2's exported
/// library is imported directly into NeoStation's PS2 catalogue. If a matching
/// physical PS2 row already exists, it is kept; otherwise NeoStation stores the
/// exported ARMSX2 launch URL as a virtual ROM path. This lets the PS2 console
/// appear in the main menu even when ARMSX2 and RetroArch share one ROM folder
/// whose layout does not match NeoStation's folder-based detector.
class Armsx2LibraryService {
  Armsx2LibraryService._();

  static final _log = LoggerService.instance;

  static const String _callbackScheme = 'neostation';
  static const String _callbackHost = 'armsx2';
  static const String _prefsKey = 'armsx2_library_cache_v1';
  static const String _virtualScheme = 'armsx2';

  /// Lookup keys (filename / basename / extensionless stem) -> raw ARMSX2
  /// exported game entry.
  static Map<String, Map<String, dynamic>>? _cache;

  /// True for NeoStation rows backed by an ARMSX2 deeplink instead of a local
  /// filesystem path.
  static bool isVirtualLibraryPath(String romPath) {
    final uri = Uri.tryParse(romPath);
    if (uri == null || uri.scheme.toLowerCase() != _virtualScheme) {
      return false;
    }
    final route = <String>{
      if (uri.host.isNotEmpty) uri.host.toLowerCase(),
      ...uri.pathSegments.map((segment) => segment.toLowerCase()),
    };
    return route.contains('launch') ||
        route.contains('boot') ||
        route.contains('play');
  }

  /// Opens ARMSX2 and requests a fresh export of its game library.
  ///
  /// Completion is asynchronous: ARMSX2 switches back to NeoStation through
  /// the callback URL, which is processed by [handleIncomingUri].
  static Future<bool> requestLibrarySync() async {
    final callback = Uri(
      scheme: _callbackScheme,
      host: _callbackHost,
    ).toString();

    final uri = Uri(
      scheme: 'armsx2',
      host: 'library',
      queryParameters: {'callback': callback},
    );

    await _writeDebugFile(
      'armsx2_sync_debug.txt',
      'STATE: REQUESTED\n'
          'Request URL: $uri\n'
          'Callback expected: $callback\n\n'
          'If this file still says REQUESTED after returning to NeoStation, '
          'ARMSX2 did not send a callback to NeoStation.',
    );

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) {
        await _appendDebugFile(
          'armsx2_sync_debug.txt',
          '\nlaunchUrl returned false: ARMSX2 could not be opened.',
        );
      }
      return opened;
    } catch (e) {
      _log.e('Armsx2LibraryService: failed to request library sync: $e');
      await _appendDebugFile(
        'armsx2_sync_debug.txt',
        '\nERROR opening ARMSX2: $e',
      );
      return false;
    }
  }

  /// Handles ARMSX2's `neostation://armsx2?...&payload=...` callback.
  /// Returns true only when the URI belongs to this service and was parsed.
  static Future<bool> handleIncomingUri(Uri uri) async {
    if (uri.scheme.toLowerCase() != _callbackScheme ||
        uri.host.toLowerCase() != _callbackHost) {
      return false;
    }

    await _writeDebugFile(
      'armsx2_sync_debug.txt',
      'STATE: CALLBACK_RECEIVED\nURI: $uri',
    );

    final payloadParam = uri.queryParameters['payload'];
    if (payloadParam == null || payloadParam.isEmpty) {
      _log.w('Armsx2LibraryService: callback with no "payload" param');
      await _appendDebugFile(
        'armsx2_sync_debug.txt',
        '\nERROR: callback contained no payload parameter.',
      );
      return false;
    }

    try {
      final normalized = base64Url.normalize(payloadParam);
      final jsonBytes = base64Url.decode(normalized);
      final decoded = jsonDecode(utf8.decode(jsonBytes));

      if (decoded is! Map) {
        _log.e('Armsx2LibraryService: decoded payload is not an object');
        await _appendDebugFile(
          'armsx2_sync_debug.txt',
          '\nERROR: decoded payload is not a JSON object.',
        );
        return false;
      }

      final payload = Map<String, dynamic>.from(decoded);
      final gamesRaw = payload['games'];
      if (gamesRaw is! List) {
        _log.e('Armsx2LibraryService: payload has no games array');
        await _appendDebugFile(
          'armsx2_sync_debug.txt',
          '\nERROR: payload has no games array.\nDecoded payload: $payload',
        );
        return false;
      }

      final byFilename = <String, Map<String, dynamic>>{};
      final games = <Map<String, dynamic>>[];
      for (final entry in gamesRaw) {
        if (entry is! Map) continue;

        final map = Map<String, dynamic>.from(entry);
        final fileName = map['fileName']?.toString();
        if (fileName == null || fileName.isEmpty) continue;

        games.add(map);
        _index(byFilename, fileName, map);
        _index(byFilename, path.basename(fileName), map);
        _index(byFilename, path.basenameWithoutExtension(fileName), map);
      }

      _cache = byFilename;
      await _persist(byFilename);

      final importResult = await _importIntoNeoStation(games);

      _log.i(
        'Armsx2LibraryService: synced ${games.length} games from ARMSX2; '
        '${importResult.virtualRows} virtual rows, '
        '${importResult.physicalRows} existing physical rows',
      );

      await _writeDebugFile(
        'armsx2_sync_debug.txt',
        'STATE: IMPORTED\n'
            'Schema: ${payload['schema'] ?? 'unknown'}\n'
            'App: ${payload['app'] ?? 'unknown'}\n'
            'Version: ${payload['version'] ?? 'unknown'}\n'
            'ARMSX2 games: ${games.length}\n'
            'NeoStation virtual PS2 rows: ${importResult.virtualRows}\n'
            'Existing physical PS2 rows reused: ${importResult.physicalRows}\n'
            'Stale ARMSX2 rows removed: ${importResult.removedRows}\n'
            'PS2 rows now in NeoStation: ${importResult.totalPs2Rows}\n\n'
            'Payload:\n${const JsonEncoder.withIndent('  ').convert(payload)}',
      );

      await _refreshNeoStationUi();
      return true;
    } catch (e, stack) {
      _log.e('Armsx2LibraryService: failed to parse/import callback: $e');
      await _writeDebugFile(
        'armsx2_sync_debug.txt',
        'STATE: ERROR\n'
            'Failed to parse/import callback.\n'
            'URI: $uri\n'
            'Error: $e\n'
            'Stack: $stack',
      );
      return false;
    }
  }

  /// Imports the exported ARMSX2 library into NeoStation's PS2 catalogue.
  ///
  /// Existing physical rows are preferred. Games which NeoStation has never
  /// scanned get a virtual `armsx2://launch?...` row, which is enough for the
  /// PS2 system and game list to render and launch directly through ARMSX2.
  static Future<({
    int virtualRows,
    int physicalRows,
    int removedRows,
    int totalPs2Rows,
  })> _importIntoNeoStation(List<Map<String, dynamic>> games) async {
    final ps2 = await SystemRepository.getSystemByFolderName('ps2');
    if (ps2?.id == null) {
      throw StateError('NeoStation PS2 system definition was not found');
    }

    final db = await SqliteService.getDatabase();
    final existingRows = await db.rawQuery(
      'SELECT filename, rom_path FROM user_roms WHERE app_system_id = ?',
      [ps2!.id!],
    );

    final physicalFilenames = <String>{};
    for (final row in existingRows) {
      final fileName = row['filename']?.toString();
      final romPath = row['rom_path']?.toString() ?? '';
      if (fileName == null || fileName.isEmpty) continue;
      if (!isVirtualLibraryPath(romPath)) {
        physicalFilenames.add(fileName.toLowerCase());
      }
    }

    final desiredVirtualPaths = <String>{};
    var virtualRows = 0;
    var physicalRows = 0;

    await db.transaction((txn) async {
      for (final game in games) {
        final fileName = game['fileName']?.toString();
        if (fileName == null || fileName.isEmpty) continue;

        if (physicalFilenames.contains(fileName.toLowerCase())) {
          physicalRows++;
          continue;
        }

        final title = game['title']?.toString();
        final serial = game['serial']?.toString();
        final exportedLaunchUrl = game['launchURL']?.toString();
        final parsedExported = exportedLaunchUrl == null
            ? null
            : Uri.tryParse(exportedLaunchUrl);
        final launchUri = parsedExported != null &&
                parsedExported.scheme.toLowerCase() == _virtualScheme
            ? parsedExported
            : Uri(
                scheme: _virtualScheme,
                host: 'launch',
                queryParameters: {'game': fileName},
              );
        final virtualPath = launchUri.toString();
        desiredVirtualPaths.add(virtualPath);

        await txn.rawInsert(
          '''
          INSERT INTO user_roms
            (app_system_id, app_emulator_unique_id, app_emulator_os_id,
             filename, rom_path, title_id, title_name, created_at, updated_at)
          VALUES (?, NULL, NULL, ?, ?, ?, ?, datetime('now'), datetime('now'))
          ON CONFLICT(rom_path) DO UPDATE SET
            app_system_id = excluded.app_system_id,
            filename = excluded.filename,
            title_id = CASE
              WHEN user_roms.title_id IS NULL OR user_roms.title_id = ''
              THEN excluded.title_id ELSE user_roms.title_id END,
            title_name = CASE
              WHEN user_roms.title_name IS NULL OR user_roms.title_name = ''
              THEN excluded.title_name ELSE user_roms.title_name END,
            updated_at = datetime('now')
          ''',
          [ps2.id!, fileName, virtualPath, serial, title],
        );
        virtualRows++;
      }
    });

    // Remove only stale virtual ARMSX2 rows. Physical PS2 rows and all their
    // user metadata remain untouched.
    final virtualRowsInDb = await db.rawQuery(
      "SELECT rom_path FROM user_roms WHERE app_system_id = ? AND rom_path LIKE 'armsx2://%'",
      [ps2.id!],
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
            [ps2.id!, ...batch],
          );
        }
      });
    }

    final countRows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM user_roms WHERE app_system_id = ?',
      [ps2.id!],
    );
    final totalPs2Rows = int.tryParse('${countRows.first['count'] ?? 0}') ?? 0;

    if (totalPs2Rows > 0) {
      await SystemRepository.addDetectedSystem(ps2.id!, 'ps2');
    } else {
      await SystemRepository.removeDetectedSystem(ps2.id!);
    }

    return (
      virtualRows: virtualRows,
      physicalRows: physicalRows,
      removedRows: removedRows,
      totalPs2Rows: totalPs2Rows,
    );
  }

  static Future<void> _refreshNeoStationUi() async {
    try {
      final context = rootNavigatorKey.currentContext;
      if (context == null) return;

      await Provider.of<SqliteDatabaseProvider>(
        context,
        listen: false,
      ).loadGamesForSystem('ps2');
      await Provider.of<SqliteConfigProvider>(
        context,
        listen: false,
      ).refreshDetectedSystems();
    } catch (e) {
      _log.e('Armsx2LibraryService: UI refresh failed: $e');
    }
  }

  static void _index(
    Map<String, Map<String, dynamic>> target,
    String key,
    Map<String, dynamic> entry,
  ) {
    if (key.isEmpty) return;
    target[key] = entry;
    target.putIfAbsent(key.toLowerCase(), () => entry);
  }

  /// Loads the last ARMSX2 export from SharedPreferences at app startup.
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
      _log.e('Armsx2LibraryService: failed loading cached library: $e');
      _cache = {};
    }
  }

  static Future<void> _persist(Map<String, Map<String, dynamic>> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(data));
    } catch (e) {
      _log.e('Armsx2LibraryService: failed persisting library cache: $e');
    }
  }

  /// Whether a non-empty ARMSX2 library has been received at least once.
  static bool get hasSyncedLibrary => (_cache?.isNotEmpty ?? false);

  /// Launches a ROM directly in ARMSX2 when it matches the most recently
  /// exported library. Virtual library rows can be launched without a cache
  /// lookup because their `rom_path` is already ARMSX2's exported launch URL.
  static Future<bool> launchGameByRomPath(String romPath) async {
    if (isVirtualLibraryPath(romPath)) {
      try {
        final uri = Uri.parse(romPath);
        await _writeDebugFile(
          'armsx2_shortcut_launch_debug.txt',
          'STATE: SHORTCUT_REQUESTED\n'
              'Shortcut: ${IosShortcutJitLaunchService.armsx2ShortcutName}\n'
              'Game URL: $uri\n'
              'Source: virtual ARMSX2 library row',
        );
        return await IosShortcutJitLaunchService.run(
          shortcutName: IosShortcutJitLaunchService.armsx2ShortcutName,
          input: uri.toString(),
        );
      } catch (e) {
        _log.e('Armsx2LibraryService: virtual launch failed: $e');
        return false;
      }
    }

    final cache = _cache;
    if (cache == null || cache.isEmpty) {
      await _writeDebugFile(
        'armsx2_launch_debug.txt',
        'romPath: $romPath\ncache is null or empty (sync ARMSX2 first)',
      );
      return false;
    }

    final basename = path.basename(romPath);
    final stem = path.basenameWithoutExtension(romPath);
    final entry =
        cache[basename] ??
        cache[basename.toLowerCase()] ??
        cache[romPath] ??
        cache[romPath.toLowerCase()] ??
        cache[stem] ??
        cache[stem.toLowerCase()];

    await _writeDebugFile(
      'armsx2_launch_debug.txt',
      'romPath: $romPath\n'
          'basename: $basename\n'
          'stem: $stem\n'
          'match found: ${entry != null}\n'
          'matched entry: ${entry != null ? jsonEncode(entry) : 'none'}\n'
          'cache keys (${cache.length}):\n${cache.keys.join('\n')}',
    );

    if (entry == null) return false;

    final fileName = entry['fileName']?.toString();
    if (fileName == null || fileName.isEmpty) return false;

    final exportedLaunchUrl = entry['launchURL']?.toString();
    final exportedUri = exportedLaunchUrl == null
        ? null
        : Uri.tryParse(exportedLaunchUrl);

    final uri = exportedUri ??
        Uri(
          scheme: 'armsx2',
          host: 'launch',
          queryParameters: {'game': fileName},
        );

    try {
      await _writeDebugFile(
        'armsx2_shortcut_launch_debug.txt',
        'STATE: SHORTCUT_REQUESTED\n'
            'Shortcut: ${IosShortcutJitLaunchService.armsx2ShortcutName}\n'
            'Game URL: $uri\n'
            'Source ROM: $romPath',
      );
      return await IosShortcutJitLaunchService.run(
        shortcutName: IosShortcutJitLaunchService.armsx2ShortcutName,
        input: uri.toString(),
      );
    } catch (e) {
      _log.e('Armsx2LibraryService: failed to launch $uri through Shortcut: $e');
      await _writeDebugFile(
        'armsx2_shortcut_launch_debug.txt',
        'STATE: ERROR\n'
            'Shortcut: ${IosShortcutJitLaunchService.armsx2ShortcutName}\n'
            'Game URL: $uri\n'
            'Error: $e',
      );
      return false;
    }
  }

  /// Device-readable diagnostics for CI-only iOS development where an Xcode
  /// console is not available.
  static Future<void> _writeDebugFile(String name, String content) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final file = File(path.join(docsDir.path, name));
      await file.writeAsString('--- ${DateTime.now()} ---\n$content');
    } catch (e) {
      _log.e('Armsx2LibraryService: failed writing debug file $name: $e');
    }
  }

  static Future<void> _appendDebugFile(String name, String content) async {
    try {
      final docsDir = await getApplicationDocumentsDirectory();
      final file = File(path.join(docsDir.path, name));
      await file.writeAsString(content, mode: FileMode.append);
    } catch (e) {
      _log.e('Armsx2LibraryService: failed appending debug file $name: $e');
    }
  }
}
