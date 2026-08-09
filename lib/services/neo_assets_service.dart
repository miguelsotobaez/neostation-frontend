import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'config_service.dart';
import 'logger_service.dart';
import '../utils/bounded_concurrency.dart';

const _baseRaw =
    'https://raw.githubusercontent.com/misobadev/neostation-assets/main';
const _manifestUrl = '$_baseRaw/manifest.json';

final _log = LoggerService.instance;

/// Represents a plan for downloading or updating theme assets.
class ThemeDownloadPlan {
  /// Whether a full redownload is required due to a version mismatch.
  final bool forceRedownload;

  /// The total number of individual asset files that need to be fetched.
  final int totalAssetsToDownload;

  /// The version string of the theme currently stored locally.
  final String? localVersion;

  /// The version string of the theme available on the remote repository.
  final String? remoteVersion;

  /// Full metadata retrieved from the remote theme configuration.
  final Map<String, dynamic>? remoteMetadata;

  /// The system folders whose backgrounds this theme actually provides,
  /// intersected with the user's systems. When the theme declares a `systems`
  /// list in `theme.json` this excludes uncovered systems entirely (no 404
  /// probes); otherwise it falls back to all of the user's systems.
  final List<String> systemsToDownload;

  const ThemeDownloadPlan({
    required this.forceRedownload,
    required this.totalAssetsToDownload,
    required this.localVersion,
    required this.remoteVersion,
    required this.remoteMetadata,
    required this.systemsToDownload,
  });
}

/// Model representing a theme available in the NeoStation assets repository.
class NeoAssetsTheme {
  /// Display name of the theme.
  final String name;

  /// The unique folder identifier for the theme.
  final String folder;

  /// The direct URL to the theme's preview image.
  final String previewUrl;

  /// The raw source path or URL for the preview image.
  final String previewSource;

  /// Whether the theme assets were generated using AI.
  final bool isAi;

  const NeoAssetsTheme({
    required this.name,
    required this.folder,
    required this.previewUrl,
    required this.previewSource,
    required this.isAi,
  });

  factory NeoAssetsTheme.fromJson(Map<String, dynamic> json) {
    final previewSource = json['preview']?.toString().trim() ?? '';
    return NeoAssetsTheme(
      name: json['name']?.toString() ?? '',
      folder: json['folder']?.toString() ?? '',
      previewUrl: _resolvePreviewUrl(previewSource),
      previewSource: previewSource,
      isAi: _parseAi(json['ai']),
    );
  }

  NeoAssetsTheme copyWith({
    String? name,
    String? folder,
    String? previewUrl,
    String? previewSource,
    bool? isAi,
  }) {
    return NeoAssetsTheme(
      name: name ?? this.name,
      folder: folder ?? this.folder,
      previewUrl: previewUrl ?? this.previewUrl,
      previewSource: previewSource ?? this.previewSource,
      isAi: isAi ?? this.isAi,
    );
  }

  /// Parses various dynamic types into a boolean flag for AI attribution.
  static bool _parseAi(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      return normalized == 'true' || normalized == '1' || normalized == 'yes';
    }
    return false;
  }

  /// Resolves raw preview strings into usable image URLs, including GitHub blob
  /// translation and WebP conversion heuristics.
  static String _resolvePreviewUrl(dynamic rawPreview) {
    final preview = rawPreview?.toString().trim() ?? '';
    if (preview.isEmpty) return '';

    final uri = Uri.tryParse(preview);
    if (uri != null && uri.hasScheme) {
      if (uri.host == 'github.com' && uri.pathSegments.length >= 5) {
        final segments = uri.pathSegments;
        if (segments[2] == 'blob') {
          final owner = segments[0];
          final repo = segments[1];
          final branch = segments[3];
          final filePath = segments.sublist(4).join('/');
          return _forceWebpPreviewUrl(
            'https://raw.githubusercontent.com/$owner/$repo/$branch/$filePath',
          );
        }
      }
      return _forceWebpPreviewUrl(preview);
    }

    final normalizedPath = preview.startsWith('/')
        ? preview.substring(1)
        : preview;
    return _forceWebpPreviewUrl('$_baseRaw/$normalizedPath');
  }

  /// Appends or replaces the image extension with .webp if it's a standard format.
  static String _forceWebpPreviewUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;

    final path = uri.path;
    final lowerPath = path.toLowerCase();
    if (!lowerPath.endsWith('.jpg') &&
        !lowerPath.endsWith('.jpeg') &&
        !lowerPath.endsWith('.png')) {
      return url;
    }

    final newPath = path.replaceFirst(
      RegExp(r'\.(jpg|jpeg|png)$', caseSensitive: false),
      '.webp',
    );
    return uri.replace(path: newPath).toString();
  }

  /// Public preview-URL normalizer shared by the UIs (system-art settings grid
  /// and the setup wizard) so they render the exact same image. Handles legacy
  /// embedded-GitHub URLs, GitHub blob→raw translation, and WebP conversion.
  static String normalizePreviewUrl(String value) {
    var url = value.trim();
    if (url.isEmpty) return '';

    // Legacy malformed URLs like:
    // https://raw.../https://github.com/owner/repo/blob/main/file.webp
    final embeddedGithub = RegExp(
      r'https?://github\.com/[^\s]+',
    ).firstMatch(url);
    if (embeddedGithub != null) {
      url = embeddedGithub.group(0)!;
    }

    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return url;

    if (uri.host == 'github.com' &&
        uri.pathSegments.length >= 5 &&
        uri.pathSegments[2] == 'blob') {
      final owner = uri.pathSegments[0];
      final repo = uri.pathSegments[1];
      final branch = uri.pathSegments[3];
      final filePath = uri.pathSegments.sublist(4).join('/');
      return _forceWebpPreviewUrl(
        'https://raw.githubusercontent.com/$owner/$repo/$branch/$filePath',
      );
    }

    return _forceWebpPreviewUrl(url);
  }
}

/// Service responsible for fetching, downloading, and caching remote assets
/// (themes, logos, backgrounds) from the NeoStation assets repository.
class NeoAssetsService {
  static List<NeoAssetsTheme>? _cachedThemes;
  static String? _cachedThemeDir;

  /// Fetches the global manifest of available themes.
  ///
  /// Tries the remote manifest first (caching it to disk on success), then
  /// falls back to the last cached manifest when the network is unavailable.
  /// The result is always floored with locally-downloaded theme folders so an
  /// already-applied pack stays visible and selectable in the settings list
  /// even offline — e.g. when NeoStation is the home launcher and cold-starts
  /// at boot before wifi connects (the manifest fetch fails then, and without
  /// this fallback the list collapses to just "None" while the theme is in
  /// fact still applied and rendering from cache).
  static Future<List<NeoAssetsTheme>> fetchThemes() async {
    if (_cachedThemes != null) return _cachedThemes!;

    final remote = await _fetchRemoteThemes();
    if (remote != null) {
      final merged = await _mergeWithLocalThemes(remote);
      _cachedThemes = merged;
      return merged;
    }

    // Offline: last cached manifest, floored by locally downloaded themes.
    final fallback = await _mergeWithLocalThemes(await _readCachedManifest());
    if (fallback.isNotEmpty) {
      _log.i('Themes: offline fallback served ${fallback.length} theme(s)');
      _cachedThemes = fallback;
      return fallback;
    }
    return [];
  }

  /// Fetches and enriches the remote theme manifest, persisting it to disk for
  /// offline reuse. Returns null on any network failure so callers can fall
  /// back to the on-disk copy.
  static Future<List<NeoAssetsTheme>?> _fetchRemoteThemes() async {
    try {
      final response = await http.get(Uri.parse(_manifestUrl));
      if (response.statusCode != 200) {
        _log.w(
          'Failed to fetch neostation-assets manifest: ${response.statusCode}',
        );
        return null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // Persist the raw manifest so the theme list survives offline boots.
      await _writeCachedManifest(response.body);
      final baseList = (json['themes'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(NeoAssetsTheme.fromJson)
          .toList();
      return Future.wait(
        baseList.map((theme) async {
          final metadata = await _fetchThemeMetadata(theme.folder);
          if (metadata == null) return theme;
          final metadataAi = NeoAssetsTheme._parseAi(metadata['ai']);
          if (metadataAi == theme.isAi) return theme;
          return theme.copyWith(isAi: metadataAi);
        }),
      );
    } catch (e) {
      _log.e('Error fetching themes: $e');
      return null;
    }
  }

  /// On-disk path of the cached global manifest.
  static Future<String> _manifestCachePath() async {
    return path.join(await _cacheDir(), 'manifest.json');
  }

  /// Persists the raw manifest JSON body to the theme cache directory.
  static Future<void> _writeCachedManifest(String body) async {
    try {
      final file = File(await _manifestCachePath());
      await file.parent.create(recursive: true);
      await file.writeAsString(body);
    } catch (e) {
      _log.w('Error caching manifest: $e');
    }
  }

  /// Reads the last successfully-fetched manifest from disk. Empty if none.
  static Future<List<NeoAssetsTheme>> _readCachedManifest() async {
    try {
      final file = File(await _manifestCachePath());
      if (!await file.exists()) return [];
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return [];
      return (json['themes'] as List? ?? [])
          .cast<Map<String, dynamic>>()
          .map(NeoAssetsTheme.fromJson)
          .toList();
    } catch (e) {
      _log.w('Error reading cached manifest: $e');
      return [];
    }
  }

  /// Builds theme entries from locally-downloaded theme folders (each carries a
  /// `theme.json`). Guarantees an applied pack appears even if it is absent
  /// from the cached manifest. Preview URLs are empty (previews are not cached),
  /// so tiles render with a placeholder — the point is selectability.
  static Future<List<NeoAssetsTheme>> _localThemes() async {
    try {
      final dir = Directory(await _cacheDir());
      if (!await dir.exists()) return [];
      final result = <NeoAssetsTheme>[];
      await for (final entry in dir.list()) {
        if (entry is! Directory) continue;
        final folder = path.basename(entry.path);
        final metaFile = File(path.join(entry.path, 'theme.json'));
        if (!await metaFile.exists()) continue;
        try {
          final json = jsonDecode(await metaFile.readAsString());
          if (json is! Map<String, dynamic>) continue;
          final name = json['name']?.toString();
          result.add(
            NeoAssetsTheme(
              name: (name == null || name.isEmpty) ? folder : name,
              folder: folder,
              previewUrl: '',
              previewSource: '',
              isAi: NeoAssetsTheme._parseAi(json['ai']),
            ),
          );
        } catch (_) {
          // Skip an unreadable theme.json rather than dropping the whole list.
        }
      }
      return result;
    } catch (e) {
      _log.w('Error enumerating local themes: $e');
      return [];
    }
  }

  /// Appends any locally-downloaded theme not already present in [base]
  /// (matched by folder), preserving [base]'s order and preview metadata.
  static Future<List<NeoAssetsTheme>> _mergeWithLocalThemes(
    List<NeoAssetsTheme> base,
  ) async {
    final local = await _localThemes();
    if (local.isEmpty) return base;
    final seen = base.map((t) => t.folder).toSet();
    final merged = [...base];
    for (final t in local) {
      if (seen.add(t.folder)) merged.add(t);
    }
    return merged;
  }

  /// Clears the in-memory theme list cache.
  static void clearCache() {
    _cachedThemes = null;
  }

  /// Returns the remote URL for a specific system background within a theme.
  static String getBackgroundUrl(
    String themeFolder,
    String systemFolderName, {
    String ext = 'webp',
  }) {
    return '$_baseRaw/themes/$themeFolder/backgrounds/$systemFolderName.$ext';
  }

  /// Returns the remote URL for a specific system logo within a theme.
  static String getLogoUrl(
    String themeFolder,
    String systemFolderName, {
    String ext = 'webp',
  }) {
    return '$_baseRaw/themes/$themeFolder/logos/$systemFolderName.$ext';
  }

  /// Returns the remote URL for a theme's metadata JSON file.
  static String getThemeMetadataUrl(String themeFolder) {
    return '$_baseRaw/themes/$themeFolder/theme.json';
  }

  /// Downloads a remote asset to the local filesystem and returns the absolute path.
  static Future<String?> downloadAndCacheAsset(
    String url,
    String localPath,
  ) async {
    try {
      final file = File(localPath);
      if (await file.exists()) return localPath;

      await file.parent.create(recursive: true);
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;

      await file.writeAsBytes(response.bodyBytes);
      return localPath;
    } catch (e) {
      _log.e('Error caching asset $url: $e');
      return null;
    }
  }

  /// Returns the local directory used for theme asset caching.
  static Future<String> _cacheDir() async {
    if (_cachedThemeDir != null) return _cachedThemeDir!;
    final base = await ConfigService.getUserDataPath();
    _cachedThemeDir = path.join(base, 'themes');
    return _cachedThemeDir!;
  }

  /// Ensures the theme cache directory path is calculated and available.
  static Future<void> ensureCacheDirInitialized() async {
    await _cacheDir();
  }

  /// Synchronous variant of background path resolution, requires previous initialization.
  static String? backgroundCachePathSync(
    String themeFolder,
    String systemFolderName, {
    String ext = 'webp',
  }) {
    final dir = _cachedThemeDir;
    if (dir == null) return null;
    return path.join(dir, themeFolder, 'backgrounds', '$systemFolderName.$ext');
  }

  /// Synchronous variant of logo path resolution, requires previous initialization.
  static String? logoCachePathSync(
    String themeFolder,
    String systemFolderName, {
    String ext = 'webp',
  }) {
    final dir = _cachedThemeDir;
    if (dir == null) return null;
    return path.join(dir, themeFolder, 'logos', '$systemFolderName.$ext');
  }

  /// Resolves the cached background path checking both .webp and .gif formats.
  /// Returns the path to the existing file, preferring .webp over .gif.
  /// If neither exists, returns the .webp path as default.
  static String? resolveBackgroundPathSync(
    String themeFolder,
    String systemFolderName,
  ) {
    final dir = _cachedThemeDir;
    if (dir == null) return null;

    final webpPath = path.join(
      dir,
      themeFolder,
      'backgrounds',
      '$systemFolderName.webp',
    );
    if (File(webpPath).existsSync()) return webpPath;

    final gifPath = path.join(
      dir,
      themeFolder,
      'backgrounds',
      '$systemFolderName.gif',
    );
    if (File(gifPath).existsSync()) return gifPath;

    return webpPath;
  }

  /// Returns the local cache path for a specific background.
  static Future<String> backgroundCachePath(
    String themeFolder,
    String systemFolderName, {
    String ext = 'webp',
  }) async {
    final dir = await _cacheDir();
    return path.join(dir, themeFolder, 'backgrounds', '$systemFolderName.$ext');
  }

  /// Returns the local cache path for a specific logo.
  static Future<String> logoCachePath(
    String themeFolder,
    String systemFolderName, {
    String ext = 'webp',
  }) async {
    final dir = await _cacheDir();
    return path.join(dir, themeFolder, 'logos', '$systemFolderName.$ext');
  }

  /// Returns the local cache path for a theme's metadata file.
  static Future<String> themeMetadataCachePath(String themeFolder) async {
    final dir = await _cacheDir();
    return path.join(dir, themeFolder, 'theme.json');
  }

  /// Fetches the metadata JSON for a specific theme from the remote repository.
  static Future<Map<String, dynamic>?> _fetchThemeMetadata(
    String themeFolder,
  ) async {
    try {
      final response = await http.get(
        Uri.parse(getThemeMetadataUrl(themeFolder)),
      );
      if (response.statusCode != 200) {
        _log.w(
          'Failed to fetch theme metadata for "$themeFolder": ${response.statusCode}',
        );
        return null;
      }
      final json = jsonDecode(response.body);
      if (json is! Map<String, dynamic>) return null;
      return json;
    } catch (e) {
      _log.w('Error fetching theme metadata for "$themeFolder": $e');
      return null;
    }
  }

  /// Reads the version string from the locally cached theme metadata.
  static Future<String?> readLocalThemeVersion(String themeFolder) async {
    try {
      final metadataPath = await themeMetadataCachePath(themeFolder);
      final file = File(metadataPath);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return json['version']?.toString();
    } catch (e) {
      _log.w('Error reading local theme metadata for "$themeFolder": $e');
      return null;
    }
  }

  /// Persists the theme metadata to the local cache.
  static Future<void> writeLocalThemeMetadata(
    String themeFolder,
    Map<String, dynamic> metadata,
  ) async {
    try {
      final metadataPath = await themeMetadataCachePath(themeFolder);
      final file = File(metadataPath);
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(metadata));
    } catch (e) {
      _log.w('Error writing local theme metadata for "$themeFolder": $e');
    }
  }

  /// Counts the number of theme assets missing from the local cache for a list
  /// of systems.
  static Future<int> countMissingThemeAssets(
    String themeFolder,
    List<String> systemFolderNames,
  ) async {
    int missing = 0;
    for (final system in systemFolderNames) {
      if (!await _backgroundResolvedOrKnownMissing(themeFolder, system)) {
        missing++;
      }
    }
    return missing;
  }

  /// Local path of the negative-cache marker for a system whose background is
  /// not provided by the theme. Lives inside the theme's `backgrounds/` dir so
  /// it is wiped by [clearThemeCache] on a version bump, re-enabling probing.
  static Future<String> _backgroundMissingMarkerPath(
    String themeFolder,
    String systemFolderName,
  ) async {
    final dir = await _cacheDir();
    return path.join(
      dir,
      themeFolder,
      'backgrounds',
      '$systemFolderName.missing',
    );
  }

  /// True when a system's background is cached (.webp/.gif) OR is known to be
  /// absent from the theme (a `.missing` marker exists). Prevents re-probing
  /// systems the pack simply does not cover on every re-selection.
  static Future<bool> _backgroundResolvedOrKnownMissing(
    String themeFolder,
    String systemFolderName,
  ) async {
    final bgWebp = await backgroundCachePath(themeFolder, systemFolderName);
    final bgGif = await backgroundCachePath(
      themeFolder,
      systemFolderName,
      ext: 'gif',
    );
    final marker = await _backgroundMissingMarkerPath(
      themeFolder,
      systemFolderName,
    );
    return await File(bgWebp).exists() ||
        await File(bgGif).exists() ||
        await File(marker).exists();
  }

  /// Records that a system's background is absent from the theme so it is not
  /// re-downloaded on subsequent selections (cleared on version bump).
  static Future<void> _writeMissingMarker(
    String themeFolder,
    String systemFolderName,
  ) async {
    try {
      final marker = File(
        await _backgroundMissingMarkerPath(themeFolder, systemFolderName),
      );
      await marker.parent.create(recursive: true);
      await marker.writeAsString('');
    } catch (e) {
      _log.w(
        'Error writing missing marker for "$themeFolder/$systemFolderName": $e',
      );
    }
  }

  /// Resolves which of the user's systems this theme actually covers.
  ///
  /// When `theme.json` declares a `systems` list, returns the intersection with
  /// the user's systems so uncovered systems are never probed (no 404s). When
  /// the list is absent (older themes / offline metadata), returns all of the
  /// user's systems and relies on the `.missing` negative-cache fallback.
  static List<String> _resolveCoveredSystems(
    Map<String, dynamic>? remoteMetadata,
    List<String> systemFolderNames,
  ) {
    final declared = remoteMetadata?['systems'];
    if (declared is! List) return systemFolderNames;
    final covered = declared.map((e) => e.toString()).toSet();
    return systemFolderNames.where(covered.contains).toList();
  }

  /// Compares local and remote versions to build a prioritized download plan.
  static Future<ThemeDownloadPlan> buildThemeDownloadPlan(
    String themeFolder,
    List<String> systemFolderNames,
  ) async {
    final remoteMetadata = await _fetchThemeMetadata(themeFolder);
    final localVersion = await readLocalThemeVersion(themeFolder);
    final remoteVersion = remoteMetadata?['version']?.toString();

    final coveredSystems = _resolveCoveredSystems(
      remoteMetadata,
      systemFolderNames,
    );

    final forceRedownload =
        localVersion != null &&
        remoteVersion != null &&
        localVersion.isNotEmpty &&
        remoteVersion.isNotEmpty &&
        localVersion != remoteVersion;

    final totalAssetsToDownload = forceRedownload
        ? coveredSystems.length
        : await countMissingThemeAssets(themeFolder, coveredSystems);

    _log.i(
      'buildThemeDownloadPlan[$themeFolder]: '
      'localVersion=$localVersion remoteVersion=$remoteVersion '
      'forceRedownload=$forceRedownload '
      'covered=${coveredSystems.length}/${systemFolderNames.length} '
      'missing=$totalAssetsToDownload',
    );

    return ThemeDownloadPlan(
      forceRedownload: forceRedownload,
      totalAssetsToDownload: totalAssetsToDownload,
      localVersion: localVersion,
      remoteVersion: remoteVersion,
      remoteMetadata: remoteMetadata,
      systemsToDownload: coveredSystems,
    );
  }

  /// Retrieves a cached background image, downloading it if necessary.
  /// Tries .webp first, then falls back to .gif.
  static Future<String?> getCachedBackground(
    String themeFolder,
    String systemFolderName,
  ) async {
    final webpPath = await backgroundCachePath(themeFolder, systemFolderName);
    final webpUrl = getBackgroundUrl(themeFolder, systemFolderName);
    var result = await downloadAndCacheAsset(webpUrl, webpPath);
    if (result != null) return result;

    final gifPath = await backgroundCachePath(
      themeFolder,
      systemFolderName,
      ext: 'gif',
    );
    final gifUrl = getBackgroundUrl(themeFolder, systemFolderName, ext: 'gif');
    result = await downloadAndCacheAsset(gifUrl, gifPath);
    if (result != null) return result;

    // Neither format exists remotely: record a negative-cache marker so this
    // system is not re-probed on every re-selection of the theme.
    await _writeMissingMarker(themeFolder, systemFolderName);
    return null;
  }

  /// Retrieves a cached system logo image, downloading it if necessary.
  static Future<String?> getCachedLogo(
    String themeFolder,
    String systemFolderName,
  ) async {
    final localPath = await logoCachePath(themeFolder, systemFolderName);
    final url = getLogoUrl(themeFolder, systemFolderName);
    return downloadAndCacheAsset(url, localPath);
  }

  /// Max background downloads in flight at once. Theme assets are small,
  /// independent HTTP GETs, so a bounded pool cuts wall-clock time roughly
  /// linearly without overwhelming the network or the host.
  static const int _downloadConcurrency = 8;

  /// Downloads all background and logo assets for a theme, optionally
  /// forcing a refresh.
  static Future<void> downloadAllThemeAssets(
    String themeFolder,
    List<String> systemFolderNames, {
    bool forceRedownload = false,
    void Function(int done, int total)? onProgress,
  }) async {
    if (forceRedownload) {
      await clearThemeCache(themeFolder);
    }

    final total = systemFolderNames.length;
    int done = 0;
    await runBounded<String>(
      systemFolderNames,
      _downloadConcurrency,
      (system) => getCachedBackground(themeFolder, system),
      onEach: () => onProgress?.call(++done, total),
    );
  }

  /// Downloads only the missing background and logo assets for a theme.
  static Future<void> downloadMissingThemeAssets(
    String themeFolder,
    List<String> systemFolderNames, {
    required int missingTotal,
    void Function(int done, int total)? onProgress,
  }) async {
    if (missingTotal <= 0) return;

    // Skip systems already cached or known to be absent from the theme.
    final pending = <String>[];
    for (final system in systemFolderNames) {
      if (!await _backgroundResolvedOrKnownMissing(themeFolder, system)) {
        pending.add(system);
      }
    }

    int done = 0;
    // getCachedBackground tries .webp then .gif and records a negative-cache
    // marker when neither exists remotely.
    await runBounded<String>(
      pending,
      _downloadConcurrency,
      (system) => getCachedBackground(themeFolder, system),
      onEach: () => onProgress?.call(++done, missingTotal),
    );
  }

  /// Deletes all cached assets for a specific theme folder.
  static Future<void> clearThemeCache(String themeFolder) async {
    try {
      final dir = await _cacheDir();
      final themeDir = Directory(path.join(dir, themeFolder));
      if (await themeDir.exists()) {
        await themeDir.delete(recursive: true);
      }
    } catch (e) {
      _log.e('Error clearing theme cache: $e');
    }
  }
}
