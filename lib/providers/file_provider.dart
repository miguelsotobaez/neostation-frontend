import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/repositories/system_repository.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:neostation/services/config_service.dart';
import 'package:neostation/services/logger_service.dart';

/// Provider responsible for abstracting filesystem access across Android and Desktop platforms.
///
/// Handles resolution of system-specific paths for user data, game media
/// (screenshots, videos), and localized assets. Implements smart ROM extension
/// stripping and standardizes I/O operations.
class FileProvider extends ChangeNotifier {
  /// Default folder name for internal user configuration and database.
  static const String userDataFolder = 'user-data';

  /// Default folder name for game artwork and media assets.
  static const String mediaFolder = 'media';

  /// Subfolder name for game preview videos.
  static const String videosFolder = 'videos';

  /// Subfolder name for game screenshots.
  static const String screenshotsFolder = 'screenshots';

  static final _log = LoggerService.instance;

  /// Absolute path to the user-data directory.
  String? _userDataPath;

  /// Absolute path to the root media directory.
  String? _mediaPath;

  /// Absolute path to the user's standard Documents directory.
  String? _documentsPath;

  /// Whether the provider has finished resolving all platform-specific paths.
  bool _isInitialized = false;

  /// Cached map of supported file extensions per system, loaded from the database.
  Map<String, Set<String>> _systemExtensions = {};

  /// Absolute path to the user's ES-DE application folder, or null if the ES-DE
  /// import is not configured. Used for read-time fallback artwork resolution.
  String? _esdeRoot;

  /// NeoStation system folder name -> ES-DE `downloaded_media` subfolder name,
  /// captured during ES-DE import.
  Map<String, String> _esdeSystemDirs = {};

  /// "systemFolder\u0000romBase" -> ES-DE media subfolder (the ROM's directory
  /// relative to the system folder). Only populated for ROMs that live in a
  /// subfolder; ES-DE mirrors that structure inside `downloaded_media`.
  Map<String, String> _esdeMediaSubdirs = {};

  /// Builds the composite subdir-map key. The NUL separator can't occur in a
  /// folder or ROM name, and both parts are lowercased because ES-DE ROMs are
  /// matched case-insensitively at import time (so write- and read-side keys
  /// agree even when the gamelist casing differs from the scanned filename).
  static String _esdeSubdirKey(String systemFolder, String romBase) =>
      '${systemFolder.toLowerCase()}\u0000${romBase.toLowerCase()}';

  /// NeoStation media-type folder -> ES-DE `downloaded_media` categories, in
  /// preference order. ES-DE scrapes more categories than NeoStation renders
  /// and users routinely enable only some of them, so each type falls back to
  /// the next-best ES-DE category rather than showing nothing.
  static const Map<String, List<String>> _esdeMediaCategories = {
    'box2d': ['covers', '3dboxes'],
    'wheels': ['marquees'],
    'screenshots': ['screenshots', 'titlescreens', 'miximages'],
    'fanarts': ['fanart', 'miximages'],
    'videos': ['videos'],
  };

  /// Image extensions ES-DE writes into `downloaded_media`.
  static const List<String> _esdeMediaExtensions = ['png', 'jpg'];

  // Getters
  String? get userDataPath => _userDataPath;
  String? get mediaPath => _mediaPath;
  String? get documentsPath => _documentsPath;
  bool get isInitialized => _isInitialized;

  /// Resolves physical filesystem paths based on the current operating system.
  ///
  /// On Android, prioritizes Scoped Storage directories and internal app support paths.
  /// On Desktop, uses paths provided by [ConfigService] or current working directory fallbacks.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final appSupportDir = await getApplicationSupportDirectory();
        _documentsPath = appSupportDir.path;
        _userDataPath = appSupportDir.path;

        if (Platform.isAndroid) {
          final userDataPath = await ConfigService.getUserDataPath();
          _mediaPath = userDataPath;
        } else {
          // iOS: this used to be appSupportDir.path directly, which pointed
          // at a completely different folder (Application Support) than
          // where scraped media is actually written
          // (ConfigService.getMediaPath(), under Documents — see
          // media_resolver.dart, steam_scraper_service.dart, etc). Images
          // would download successfully and sit on disk, but the app would
          // never find them when rendering game art, because it was
          // looking in the wrong sandbox folder entirely.
          //
          // getMediaPath() below appends `mediaFolder` ('media') back onto
          // whatever _mediaPath is set to, so — same as the desktop branch
          // further down — this needs to be the *parent* of
          // ConfigService.getMediaPath()'s result (.../Documents), not that
          // result itself (.../Documents/media), or every lookup would
          // resolve to .../Documents/media/media/....
          final fullMediaPath = await ConfigService.getMediaPath();
          _mediaPath = path.dirname(fullMediaPath);
        }
      } else {
        final userDataPath = await ConfigService.getUserDataPath();
        final userDataDir = Directory(userDataPath);
        _userDataPath = userDataDir.path;

        final fullMediaPath = await ConfigService.getMediaPath();
        _mediaPath = path.dirname(fullMediaPath);

        _documentsPath = path.dirname(userDataDir.path);
      }

      // Ensure directory structures exist.
      if (_userDataPath != null) {
        final userDataDir = Directory(_userDataPath!);
        if (!await userDataDir.exists()) {
          await userDataDir.create(recursive: true);
        }
      }

      if (_mediaPath != null) {
        final mediaDir = Directory(_mediaPath!);
        if (!await mediaDir.exists()) {
          await mediaDir.create(recursive: true);
        }
      }

      _systemExtensions = await SystemRepository.getSystemExtensionsMap();
      await _loadEsdeConfig();
      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      _log.e('FileProvider: Error initializing: $e');
      _userDataPath = null;
      _mediaPath = null;
      _documentsPath = null;
      _isInitialized = false;
      notifyListeners();
    }
  }

  /// Sanitizes a ROM filename by stripping its extension.
  ///
  /// Implements a multi-stage logic to prevent false positives:
  /// 1. Checks against the database-backed system extension whitelist.
  /// 2. Preserves version-like strings (e.g., '.v1').
  /// 3. Checks against common ROM extensions.
  /// 4. Fallback for short, non-spaced substrings following the final dot.
  String _stripRomExtension(String romName, [String? systemFolderName]) {
    final validExtensions = systemFolderName != null
        ? _systemExtensions[systemFolderName]
        : null;
    return stripRomExtension(romName, validExtensions);
  }

  /// Common ROM container/image extensions used by the extension-stripping
  /// fallback when a system-specific whitelist isn't available.
  static const Set<String> _commonRomExts = {
    'zip',
    '7z',
    'rar',
    'iso',
    'bin',
    'cue',
    'chd',
    'nes',
    'sfc',
    'smc',
    'gba',
    'gbc',
    'gb',
    'n64',
    'z64',
    'v64',
    'nds',
    '3ds',
    'cia',
    'nsp',
    'xci',
    'nca',
    'nro',
    'nso',
    'rvz',
    'wbfs',
    'gcm',
    'rpx',
  };

  /// Strips a ROM filename's extension using the same multi-stage logic
  /// everywhere (single source of truth so write-time and read-time media keys
  /// stay in agreement):
  /// 1. If [validExtensions] is given and matches, strip it.
  /// 2. Preserve version-like strings (e.g. `.v1`, `.123`).
  /// 3. Strip known common ROM extensions.
  /// 4. Fallback: strip short, non-spaced extensions.
  static String stripRomExtension(
    String romName, [
    Set<String>? validExtensions,
  ]) {
    if (!romName.contains('.')) return romName;

    final lastDot = romName.lastIndexOf('.');
    final ext = romName.substring(lastDot + 1).toLowerCase();

    if (validExtensions != null && validExtensions.contains(ext)) {
      return romName.substring(0, lastDot);
    }

    final isVersion =
        RegExp(r'^\d+$').hasMatch(ext) || RegExp(r'^v\d+').hasMatch(ext);
    if (isVersion) return romName;

    if (_commonRomExts.contains(ext)) {
      return romName.substring(0, lastDot);
    }

    if (ext.length <= 4 && !ext.contains(' ')) {
      return romName.substring(0, lastDot);
    }

    return romName;
  }

  /// Resolves the absolute path for a game's preview video.
  String getVideoPath(String systemFolderName, String romName) {
    final baseName = _stripRomExtension(romName, systemFolderName);

    if (!_isInitialized || _mediaPath == null) {
      return path.join(
        mediaFolder,
        systemFolderName,
        videosFolder,
        '$baseName.mp4',
      );
    }
    return path.join(
      _mediaPath!,
      mediaFolder,
      systemFolderName,
      videosFolder,
      '$baseName.mp4',
    );
  }

  /// Resolves the absolute path for a game's screenshot.
  String getScreenshotPath(String systemFolderName, String romName) {
    final baseName = _stripRomExtension(romName, systemFolderName);

    if (!_isInitialized || _mediaPath == null) {
      return path.join(
        mediaFolder,
        systemFolderName,
        screenshotsFolder,
        '$baseName.png',
      );
    }
    return path.join(
      _mediaPath!,
      mediaFolder,
      systemFolderName,
      screenshotsFolder,
      '$baseName.png',
    );
  }

  /// Resolves the absolute path for any specific media type and extension.
  String getMediaPath(
    String systemFolderName,
    String imageType,
    String romName,
    String extension,
  ) {
    final baseName = _stripRomExtension(romName, systemFolderName);

    if (!_isInitialized || _mediaPath == null) {
      return path.join(
        mediaFolder,
        systemFolderName,
        imageType,
        '$baseName.$extension',
      );
    }
    return path.join(
      _mediaPath!,
      mediaFolder,
      systemFolderName,
      imageType,
      '$baseName.$extension',
    );
  }

  /// Joins a relative path with the absolute user-data directory.
  String getAbsolutePath(String relativePath) {
    if (!_isInitialized || _userDataPath == null) {
      return path.join(userDataFolder, relativePath);
    }
    return path.join(_userDataPath!, relativePath);
  }

  /// Resolves the expected internal path for a ROM file.
  String getRomPath(String systemFolderName, String romName) {
    if (!_isInitialized || _userDataPath == null) {
      return path.join(
        userDataFolder,
        'roms',
        systemFolderName,
        '$romName.zip',
      );
    }
    return path.join(_userDataPath!, 'roms', systemFolderName, '$romName.zip');
  }

  /// Checks if a file exists asynchronously.
  Future<bool> fileExists(String filePath) async {
    try {
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      _log.e('Error checking file existence $filePath: $e');
      return false;
    }
  }

  /// Recursively creates the parent directories for a given file path if they do not exist.
  Future<void> ensureDirectoryExists(String filePath) async {
    try {
      final directory = Directory(path.dirname(filePath));
      if (!await directory.exists()) {
        await directory.create(recursive: true);
      }
    } catch (e) {
      _log.e('Error creating directory for $filePath: $e');
    }
  }

  /// Returns a list of all files and directories within a given path.
  Future<List<FileSystemEntity>> getFilesInDirectory(
    String directoryPath,
  ) async {
    try {
      final directory = Directory(directoryPath);
      if (await directory.exists()) {
        return directory.list().toList();
      }
      return [];
    } catch (e) {
      _log.e('Error listing files in $directoryPath: $e');
      return [];
    }
  }

  /// Retrieves the file size in bytes.
  Future<int> getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
      return 0;
    } catch (e) {
      _log.e('Error getting file size $filePath: $e');
      return 0;
    }
  }

  /// Copies a file to a new location, ensuring destination directories exist.
  Future<bool> copyFile(String sourcePath, String destinationPath) async {
    try {
      await ensureDirectoryExists(destinationPath);
      final sourceFile = File(sourcePath);
      await sourceFile.copy(destinationPath);
      return true;
    } catch (e) {
      _log.e('Error copying file $sourcePath to $destinationPath: $e');
      return false;
    }
  }

  /// Deletes a file from the filesystem if it exists.
  Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
      return false;
    } catch (e) {
      _log.e('Error deleting file $filePath: $e');
      return false;
    }
  }

  /// Returns the system's Documents directory path.
  String getDocumentsPath() {
    return _documentsPath ?? Directory.current.path;
  }

  /// Returns the absolute path to the application's user-data directory.
  String getAppDirectoryPath() {
    return _userDataPath ?? userDataFolder;
  }

  /// Returns the absolute path to the application's root media directory.
  String getMediaDirectoryPath() {
    if (!_isInitialized || _mediaPath == null) {
      return mediaFolder;
    }
    return path.join(_mediaPath!, mediaFolder);
  }

  /// Loads ES-DE fallback configuration (root path + per-system media dirs)
  /// from the database. Safe to call repeatedly.
  Future<void> _loadEsdeConfig() async {
    try {
      final db = await SqliteService.getDatabase();
      final cfg = await db.query(
        'user_config',
        columns: ['esde_folder_path'],
        limit: 1,
      );
      final rootRaw = cfg.isNotEmpty
          ? cfg.first['esde_folder_path']?.toString()
          : null;
      _esdeRoot = (rootRaw != null && rootRaw.trim().isNotEmpty)
          ? rootRaw.trim()
          : null;

      final map = <String, String>{};
      if (_esdeRoot != null) {
        final rows = await db.rawQuery('''
          SELECT s.folder_name AS folder_name, ss.esde_media_dir AS esde_media_dir
          FROM user_system_settings ss
          JOIN app_systems s ON s.id = ss.app_system_id
          WHERE ss.esde_media_dir IS NOT NULL AND ss.esde_media_dir != ''
        ''');
        for (final r in rows) {
          final fn = r['folder_name']?.toString();
          final ed = r['esde_media_dir']?.toString();
          if (fn != null && ed != null && ed.isNotEmpty) map[fn] = ed;
        }
      }
      _esdeSystemDirs = map;

      final subdirs = <String, String>{};
      if (_esdeRoot != null) {
        final rows = await db.rawQuery('''
          SELECT s.folder_name AS folder_name, m.filename AS filename,
                 m.esde_media_subdir AS subdir
          FROM user_screenscraper_metadata m
          JOIN app_systems s ON s.id = m.app_system_id
          WHERE m.esde_media_subdir IS NOT NULL AND m.esde_media_subdir != ''
        ''');
        for (final r in rows) {
          final fn = r['folder_name']?.toString();
          final file = r['filename']?.toString();
          final sub = r['subdir']?.toString();
          if (fn == null || file == null || sub == null || sub.isEmpty) {
            continue;
          }
          final base = _stripRomExtension(file, fn);
          subdirs[_esdeSubdirKey(fn, base)] = sub;
        }
      }
      _esdeMediaSubdirs = subdirs;
    } catch (e) {
      _esdeRoot = null;
      _esdeSystemDirs = {};
      _esdeMediaSubdirs = {};
    }
  }

  /// Reloads ES-DE fallback configuration after an import and notifies
  /// listeners so views re-resolve artwork.
  Future<void> refreshEsde() async {
    await _loadEsdeConfig();
    notifyListeners();
  }

  /// Candidate read-time fallback paths for a media asset inside the user's
  /// ES-DE `downloaded_media` tree, most-preferred first, or empty if ES-DE is
  /// not configured for this system / media type. Does NOT check existence —
  /// the caller stats them in order.
  ///
  /// Candidates cover every ES-DE category mapped to [imageType] and every
  /// extension ES-DE writes. When the import recorded a media subfolder for
  /// this ROM the subfolder is tried first, then the category root: ES-DE can
  /// list one ROM filename in several subfolders and only one of them is
  /// recorded, so the root is where the art often actually sits.
  List<String> getEsdeMediaCandidates(
    String systemFolderName,
    String imageType,
    String romName,
  ) {
    if (_esdeRoot == null) return const [];
    final esdeDir = _esdeSystemDirs[systemFolderName];
    if (esdeDir == null) return const [];
    final categories = _esdeMediaCategories[imageType];
    if (categories == null) return const [];
    final baseName = _stripRomExtension(romName, systemFolderName);
    final subdir =
        _esdeMediaSubdirs[_esdeSubdirKey(systemFolderName, baseName)];
    final subdirs = <String>[
      if (subdir != null && subdir.isNotEmpty) subdir,
      '',
    ];

    final candidates = <String>[];
    for (final category in categories) {
      for (final sub in subdirs) {
        for (final extension in _esdeMediaExtensions) {
          candidates.add(
            path.joinAll([
              _esdeRoot!,
              'downloaded_media',
              esdeDir,
              category,
              if (sub.isNotEmpty) sub,
              '$baseName.$extension',
            ]),
          );
        }
      }
    }
    return candidates;
  }

  /// Resolves the read-time fallback path for a preview video inside the user's
  /// ES-DE `downloaded_media` tree, or null if ES-DE is not configured for this
  /// system. Does NOT check existence.
  String? getEsdeVideoPath(String systemFolderName, String romName) {
    if (_esdeRoot == null) return null;
    final esdeDir = _esdeSystemDirs[systemFolderName];
    if (esdeDir == null) return null;
    final baseName = _stripRomExtension(romName, systemFolderName);
    final subdir =
        _esdeMediaSubdirs[_esdeSubdirKey(systemFolderName, baseName)];
    return path.joinAll([
      _esdeRoot!,
      'downloaded_media',
      esdeDir,
      'videos',
      if (subdir != null && subdir.isNotEmpty) subdir,
      '$baseName.mp4',
    ]);
  }

  /// Resets the internal state of the provider.
  void reset() {
    _userDataPath = null;
    _mediaPath = null;
    _documentsPath = null;
    _esdeRoot = null;
    _esdeSystemDirs = {};
    _esdeMediaSubdirs = {};
    _isInitialized = false;
    notifyListeners();
  }
}
