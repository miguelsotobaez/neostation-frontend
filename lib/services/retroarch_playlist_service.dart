import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:neostation/services/config_service.dart';
import 'package:neostation/services/logger_service.dart';

/// Manipulates RetroArch's own playlist files (`.lpl`, JSON-formatted) to
/// enable a genuine one-tap launch on iOS.
///
/// Background: RetroArch's external integration points on iOS were all
/// tested and found not to accept a specific game as external input — the
/// Siri/Shortcuts "Play Game" action always falls back to its own picker
/// regardless of what's passed to it, confirmed by repeated on-device
/// testing. However, RetroArch also exposes a *parameter-less* "Resume Last
/// Game" Shortcuts action, which plays whatever sits at the front of
/// `content_history.lpl`. Since NeoStation has write access to RetroArch's
/// own folder (see ConfigService.linkedExternalFolderPath +
/// external_folder_access), it can make a specific game "the last one
/// played" itself, then trigger that parameter-less action.
///
/// Rather than constructing a playlist entry from scratch (which would mean
/// guessing at RetroArch's exact `db_name`/`core_path`/`crc32` conventions),
/// this copies the entry RetroArch itself already created when it scanned
/// the ROM into one of its per-system playlists — that entry is guaranteed
/// to be in a format RetroArch understands, since RetroArch wrote it.
class RetroArchPlaylistService {
  RetroArchPlaylistService._();

  static final _log = LoggerService.instance;

  static const String _historyFileName = 'content_history.lpl';
  static const Set<String> _skipFileNames = {
    'content_history.lpl',
    'content_image_history.lpl',
    'content_music_history.lpl',
    'content_video_history.lpl',
    'favorites.lpl',
  };

  /// Finds [romPath]'s existing entry in one of RetroArch's per-system
  /// playlists and copies it to the very front of `content_history.lpl`.
  ///
  /// Returns `true` if a matching entry was found and the history playlist
  /// was successfully updated — i.e. RetroArch's "Resume Last Game" action
  /// should now play this exact game. Returns `false` if nothing could be
  /// done (no linked RetroArch folder, ROM not yet scanned by RetroArch
  /// itself, or an I/O error) — callers should fall back to another launch
  /// path in that case rather than trigger "Resume Last Game" blind.
  static Future<bool> setAsMostRecent(String romPath) async {
    final debug = StringBuffer();
    debug.writeln('--- setAsMostRecent debug: ${DateTime.now()} ---');
    debug.writeln('romPath: $romPath');
    var result = false;

    try {
      final root = ConfigService.linkedExternalFolderPath;
      debug.writeln('linkedExternalFolderPath: $root');
      if (root == null) {
        debug.writeln('RESULT: false (no linked folder)');
        return false;
      }

      var playlistsDir = Directory(path.join(root, 'playlists'));
      if (!await playlistsDir.exists()) {
        // The linked folder is often the ROMs/library subfolder rather
        // than RetroArch's own root (which has playlists/, cores/, etc as
        // siblings of that subfolder) — confirmed via debug logging on a
        // real device. Try one level up before giving up.
        final parentPlaylistsDir = Directory(
          path.join(path.dirname(root), 'playlists'),
        );
        if (await parentPlaylistsDir.exists()) {
          playlistsDir = parentPlaylistsDir;
        }
      }
      debug.writeln('playlistsDir: ${playlistsDir.path}');
      debug.writeln('playlistsDir.exists(): ${await playlistsDir.exists()}');
      if (!await playlistsDir.exists()) {
        debug.writeln('RESULT: false (no playlists/ folder)');
        return false;
      }

      Map<String, dynamic>? matchingEntry;
      String? matchedInFile;

      try {
        await for (final entity in playlistsDir.list()) {
          if (entity is! File || !entity.path.endsWith('.lpl')) continue;
          final name = path.basename(entity.path);
          if (_skipFileNames.contains(name)) continue;

          try {
            final decoded = jsonDecode(await entity.readAsString());
            if (decoded is! Map<String, dynamic>) continue;
            final items = decoded['items'];
            if (items is! List) continue;

            for (final item in items) {
              if (item is Map<String, dynamic> && item['path'] == romPath) {
                matchingEntry = Map<String, dynamic>.from(item);
                matchedInFile = name;
                break;
              }
            }
          } catch (e) {
            debug.writeln('skipped unreadable ${entity.path}: $e');
            continue;
          }
          if (matchingEntry != null) break;
        }
      } catch (e) {
        debug.writeln('RESULT: false (failed listing playlists/: $e)');
        return false;
      }

      debug.writeln('matchedInFile: $matchedInFile');
      debug.writeln('matchingEntry: ${matchingEntry != null ? jsonEncode(matchingEntry) : "null"}');

      if (matchingEntry == null) {
        debug.writeln('RESULT: false (no matching entry found in any playlist)');
        return false;
      }

      final historyFile = File(path.join(playlistsDir.path, _historyFileName));
      debug.writeln('historyFile: ${historyFile.path}');
      debug.writeln('historyFile.exists(): ${await historyFile.exists()}');

      Map<String, dynamic> history;
      if (await historyFile.exists()) {
        try {
          final decoded = jsonDecode(await historyFile.readAsString());
          if (decoded is! Map<String, dynamic>) {
            debug.writeln('RESULT: false ($_historyFileName is not a JSON object)');
            return false;
          }
          history = decoded;
        } catch (e) {
          debug.writeln('RESULT: false (failed to parse $_historyFileName: $e)');
          return false;
        }
      } else {
        history = {
          'version': '1.5',
          'default_core_path': '',
          'default_core_name': '',
          'label_display_mode': 0,
          'right_thumbnail_mode': 0,
          'left_thumbnail_mode': 0,
          'thumbnail_match_mode': 0,
          'sort_mode': 0,
          'items': <dynamic>[],
        };
      }

      final historyItems = (history['items'] as List?)?.toList() ?? <dynamic>[];
      debug.writeln('historyItems.length before: ${historyItems.length}');
      historyItems.removeWhere(
        (item) => item is Map<String, dynamic> && item['path'] == romPath,
      );
      historyItems.insert(0, matchingEntry);
      history['items'] = historyItems;
      debug.writeln('historyItems.length after: ${historyItems.length}');
      debug.writeln('new first item: ${jsonEncode(historyItems.first)}');

      try {
        await historyFile.writeAsString(jsonEncode(history));
        debug.writeln('RESULT: true (wrote $_historyFileName)');
        result = true;
        return true;
      } catch (e) {
        debug.writeln('RESULT: false (failed writing $_historyFileName: $e)');
        return false;
      }
    } finally {
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final debugFile = File(
          path.join(docsDir.path, 'retroarch_playlist_debug.txt'),
        );
        await debugFile.writeAsString(debug.toString());
      } catch (e) {
        _log.e('RetroArchPlaylistService: failed writing debug file: $e');
      }
      _log.i('RetroArchPlaylistService.setAsMostRecent -> $result');
    }
  }
}
