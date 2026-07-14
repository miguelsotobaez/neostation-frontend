import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:neostation/services/config_service.dart';
import 'package:neostation/services/logger_service.dart';
import 'package:neostation/themes/custom_theme.dart';

/// Persists and loads user-imported color themes as daisyUI JSON files under
/// `<userDataPath>/custom_themes/<id>.json`.
///
/// Built-in themes are compiled Dart; imported ones only exist on disk, so this
/// service is the single source of truth for them across restarts.
class CustomThemeService {
  static final _log = LoggerService.instance;

  /// Ids that must never be shadowed by an imported theme (built-ins + the
  /// synthetic 'system' entry). Kept here to avoid a dependency cycle with
  /// ThemeProvider; callers may also pass extra reserved ids to [importFromFile].
  static const Set<String> _reservedIds = {
    'system',
    'dark',
    'light',
    'oled',
    'valentine',
    'dracula',
    'nord',
    'coffee',
    'tokyo_night',
    'retro',
    'abyss',
    'cyberpunk',
    'aqua',
    'palenight',
    'horizon',
  };

  static Future<Directory> _dir() async {
    final base = await ConfigService.getUserDataPath();
    final dir = Directory(path.join(base, 'custom_themes'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Loads every valid custom theme from disk. Corrupt/unreadable files are
  /// skipped and logged rather than aborting the whole load.
  static Future<List<CustomTheme>> loadAll() async {
    final result = <CustomTheme>[];
    try {
      final dir = await _dir();
      final files = await dir
          .list()
          .where((e) => e is File && e.path.toLowerCase().endsWith('.json'))
          .cast<File>()
          .toList();
      for (final file in files) {
        try {
          final json = jsonDecode(await file.readAsString());
          if (json is! Map<String, dynamic>) {
            throw const FormatException('Root is not a JSON object.');
          }
          result.add(CustomTheme.fromDaisyJson(json));
        } catch (e) {
          _log.w('CustomThemeService: skipping "${file.path}" ($e).');
        }
      }
    } catch (e) {
      _log.e('CustomThemeService: failed to load custom themes: $e');
    }
    return result;
  }

  /// Reads, parses and persists a daisyUI theme JSON file.
  ///
  /// [reservedIds] lets the caller add already-loaded custom ids so a fresh
  /// import never collides with them; the parsed id is suffixed (`_2`, `_3`, …)
  /// on collision. Returns the stored [CustomTheme].
  ///
  /// Throws [FormatException] on malformed input.
  static Future<CustomTheme> importFromFile(
    String filePath, {
    Set<String> reservedIds = const {},
  }) async {
    final raw = await File(filePath).readAsString();
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Root is not a JSON object.');
    }

    var parsed = CustomTheme.fromDaisyJson(decoded);

    final taken = {..._reservedIds, ...reservedIds};
    if (taken.contains(parsed.id)) {
      var i = 2;
      var candidate = '${parsed.id}_$i';
      while (taken.contains(candidate)) {
        i++;
        candidate = '${parsed.id}_$i';
      }
      final json = Map<String, dynamic>.from(parsed.rawJson)..['id'] = candidate;
      parsed = CustomTheme.fromDaisyJson(json);
    }

    final dir = await _dir();
    final out = File(path.join(dir.path, '${parsed.id}.json'));
    await out.writeAsString(jsonEncode(parsed.rawJson));
    _log.i('CustomThemeService: imported theme "${parsed.id}".');
    return parsed;
  }

  /// Deletes the on-disk file backing [id]. No-op if it is already gone.
  static Future<void> delete(String id) async {
    try {
      final dir = await _dir();
      final file = File(path.join(dir.path, '$id.json'));
      if (await file.exists()) {
        await file.delete();
        _log.i('CustomThemeService: deleted theme "$id".');
      }
    } catch (e) {
      _log.e('CustomThemeService: failed to delete "$id": $e');
    }
  }
}
