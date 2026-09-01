import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'config_service.dart';
import 'logger_service.dart';
import '../utils/bounded_concurrency.dart';

/// Assets are served from the repository's `dist/` tree, not the source tree:
/// CI re-encodes every image there against an SSIMULACRA2 floor of 80, which
/// is the same pack at ~40% of the bytes. It is a complete mirror (same folder
/// layout, same filenames), rebuilt and committed by the single-writer
/// `optimize-assets` workflow on every push that touches the source art — the
/// same workflow that already generates the `systems` list in each
/// `theme.json`, so this adds no new dependency on CI having run.
const _baseRaw =
    'https://raw.githubusercontent.com/misobadev/neostation-assets/main/dist';
const _manifestUrl = '$_baseRaw/manifest.json';

final _log = LoggerService.instance;

/// Outcome of a single remote asset fetch.
enum AssetFetchStatus {
  /// The file is on disk (freshly downloaded or already cached).
  cached,

  /// The server answered 404: the asset genuinely is not published.
  notFound,

  /// The asset could not be reached (timeout, socket error, 429, 5xx). Says
  /// nothing about whether it exists, so it must never be cached as absent.
  failed,
}

/// The status of an asset fetch plus the local path when it succeeded.
class AssetFetchResult {
  final AssetFetchStatus status;
  final String? path;

  const AssetFetchResult(this.status, [this.path]);

  /// Whether the asset is now available on disk.
  bool get isCached => status == AssetFetchStatus.cached;

  /// Whether the server positively reported the asset as absent.
  bool get isNotFound => status == AssetFetchStatus.notFound;
}

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

  /// HTTP client for every remote fetch. Swappable so tests can drive the
  /// 404-versus-transient-failure split without a network.
  static http.Client _client = http.Client();

  /// Forgets the resolved theme-cache directory so the next call re-derives it
  /// from the current user-data path.
  ///
  /// [_cacheDir] memoises the path on first use, which is at app start — before
  /// the setup wizard's first step can move the user-data location. Without
  /// this, a wizard that relocates the user data downloads the art pack into
  /// the *old* folder while the database records the pack at the new one: the
  /// art shows for the rest of that session and is gone on the next launch,
  /// with the pack still selected in System Art.
  static void resetCacheDir() {
    _cachedThemeDir = null;
  }

  /// Points the service at a stub client and a scratch cache directory.
  @visibleForTesting
  static void debugConfigure({http.Client? client, String? cacheDir}) {
    _client = client ?? http.Client();
    _cachedThemeDir = cacheDir;
    _cachedThemes = null;
  }

  /// Restores the real client and drops any test cache directory.
  @visibleForTesting
  static void debugReset() {
    _client = http.Client();
    _cachedThemeDir = null;
    _cachedThemes = null;
  }

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
      final response = await _client.get(Uri.parse(_manifestUrl));
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
      return await Future.wait(
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

  /// How long a single asset request may take before it is retried.
  static const Duration _requestTimeout = Duration(seconds: 20);

  /// Attempts per asset before giving up. Theme packs are ~100 small files
  /// pulled from a shared CDN, so the odd 429/timeout is routine.
  static const int _maxFetchAttempts = 3;

  /// Base backoff between attempts, multiplied by the attempt number.
  static const Duration _retryBackoff = Duration(milliseconds: 500);

  /// Downloads a remote asset to the local filesystem.
  ///
  /// Distinguishes a definitive HTTP 404 ([AssetFetchStatus.notFound]) from an
  /// asset that could not be reached right now ([AssetFetchStatus.failed]:
  /// timeout, socket error, 429, 5xx). Only a 404 proves the theme does not
  /// ship the file, and only a 404 may be cached as a permanent negative
  /// result — a flaky request must stay retryable, or one dropped connection
  /// blanks a system's art for the life of the install.
  ///
  /// Bytes land in a sibling `.part` file that is renamed into place only once
  /// the body is fully written, so an interrupted write can never leave a
  /// truncated image that later reads as "already cached".
  static Future<AssetFetchResult> fetchAndCacheAsset(
    String url,
    String localPath,
  ) async {
    final file = File(localPath);
    try {
      if (await file.exists()) {
        return AssetFetchResult(AssetFetchStatus.cached, localPath);
      }
    } catch (e) {
      _log.w('Error checking cached asset $localPath: $e');
    }

    for (var attempt = 1; attempt <= _maxFetchAttempts; attempt++) {
      try {
        final response = await _client
            .get(Uri.parse(url))
            .timeout(_requestTimeout);

        if (response.statusCode == 200) {
          await file.parent.create(recursive: true);
          final part = File('$localPath.part');
          await part.writeAsBytes(response.bodyBytes, flush: true);
          await part.rename(localPath);
          return AssetFetchResult(AssetFetchStatus.cached, localPath);
        }

        if (response.statusCode == 404) {
          return const AssetFetchResult(AssetFetchStatus.notFound);
        }

        _log.w(
          'Asset fetch failed ($url): HTTP ${response.statusCode} '
          '(attempt $attempt/$_maxFetchAttempts)',
        );
      } catch (e) {
        _log.w(
          'Asset fetch errored ($url): $e (attempt $attempt/$_maxFetchAttempts)',
        );
      }

      if (attempt < _maxFetchAttempts) {
        await Future.delayed(_retryBackoff * attempt);
      }
    }

    return const AssetFetchResult(AssetFetchStatus.failed);
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
      final response = await _client.get(
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
    final json = await readLocalThemeMetadata(themeFolder);
    return json?['version']?.toString();
  }

  /// Reads the cached `theme.json` for a theme, or null when it is absent or
  /// unreadable. Lets a plan fall back to the last known coverage list when
  /// the remote metadata cannot be reached.
  static Future<Map<String, dynamic>?> readLocalThemeMetadata(
    String themeFolder,
  ) async {
    try {
      final metadataPath = await themeMetadataCachePath(themeFolder);
      final file = File(metadataPath);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return null;
      return json;
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
      if (!await _backgroundCached(themeFolder, system)) {
        missing++;
      }
    }
    return missing;
  }

  /// True when a system's background is already cached (`.webp` or `.gif`).
  ///
  /// Coverage itself is decided by the theme's declared `systems` list, so an
  /// uncovered system is never probed and needs no negative-cache marker.
  static Future<bool> _backgroundCached(
    String themeFolder,
    String systemFolderName,
  ) async {
    final bgWebp = await backgroundCachePath(themeFolder, systemFolderName);
    final bgGif = await backgroundCachePath(
      themeFolder,
      systemFolderName,
      ext: 'gif',
    );
    return await File(bgWebp).exists() || await File(bgGif).exists();
  }

  /// Resolves which of the user's systems this theme actually covers.
  ///
  /// The theme's declared `systems` list is authoritative: it is generated by
  /// the same `optimize-assets` workflow that builds the `dist/` tree, so a
  /// published pack always carries one. Returning the intersection means an
  /// uncovered system is never probed, which is what makes the old `.missing`
  /// negative cache unnecessary.
  ///
  /// [localMetadata] is the on-disk `theme.json`, used when the remote copy is
  /// unreachable. If neither declares a list, coverage is empty rather than
  /// "every system": blind-probing ~100 systems is what the negative cache
  /// existed to prevent, and a visible "nothing to download" beats silently
  /// re-probing on every selection.
  static List<String> _resolveCoveredSystems(
    Map<String, dynamic>? remoteMetadata,
    Map<String, dynamic>? localMetadata,
    List<String> systemFolderNames,
  ) {
    final declared = remoteMetadata?['systems'] ?? localMetadata?['systems'];
    if (declared is! List) {
      _log.w(
        'Theme metadata declares no "systems" list; treating the pack as '
        'covering nothing rather than probing every system',
      );
      return const [];
    }
    final covered = declared.map((e) => e.toString()).toSet();
    return systemFolderNames.where(covered.contains).toList();
  }

  /// Compares local and remote versions to build a prioritized download plan.
  static Future<ThemeDownloadPlan> buildThemeDownloadPlan(
    String themeFolder,
    List<String> systemFolderNames,
  ) async {
    // Shed `.missing` markers written by older builds. They could not tell a
    // 404 from a dropped connection, so an unknown share of them are false
    // negatives that would keep a system blank forever.
    await deleteLegacyMissingMarkers();

    final remoteMetadata = await _fetchThemeMetadata(themeFolder);
    final localMetadata = await readLocalThemeMetadata(themeFolder);
    final localVersion = localMetadata?['version']?.toString();
    final remoteVersion = remoteMetadata?['version']?.toString();

    final coveredSystems = _resolveCoveredSystems(
      remoteMetadata,
      localMetadata,
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
    final webp = await fetchAndCacheAsset(webpUrl, webpPath);
    if (webp.isCached) return webp.path;

    // A transient webp failure says the server is unreachable, not that the
    // system is uncovered — probing the legacy gif would only repeat the same
    // failure (and, applied offline across ~100 systems, double the wait).
    if (!webp.isNotFound) return _unresolved(themeFolder, systemFolderName);

    final gifPath = await backgroundCachePath(
      themeFolder,
      systemFolderName,
      ext: 'gif',
    );
    final gifUrl = getBackgroundUrl(themeFolder, systemFolderName, ext: 'gif');
    final gif = await fetchAndCacheAsset(gifUrl, gifPath);
    if (gif.isCached) return gif.path;
    if (!gif.isNotFound) return _unresolved(themeFolder, systemFolderName);

    // Both formats answered 404 for a system the theme's `systems` list claims
    // to cover: the metadata has drifted from the published files. Nothing to
    // cache — the next plan re-reads the list and this corrects itself when
    // the pack is rebuilt.
    _log.w(
      'Theme "$themeFolder" declares "$systemFolderName" but ships no '
      'background for it (both .webp and .gif returned 404)',
    );
    return null;
  }

  /// Leaves a system unresolved after a transient failure. Deliberately writes
  /// no marker: the next download plan must retry it, or one flaky request
  /// during the initial ~100-file download blanks that system's art for good
  /// (the marker is cleared only by a full theme-version redownload).
  static String? _unresolved(String themeFolder, String systemFolderName) {
    _log.w(
      'Background "$themeFolder/$systemFolderName" unresolved after retries; '
      'leaving it retryable for the next theme refresh',
    );
    return null;
  }

  /// Retrieves a cached system logo image, downloading it if necessary.
  static Future<String?> getCachedLogo(
    String themeFolder,
    String systemFolderName,
  ) async {
    final localPath = await logoCachePath(themeFolder, systemFolderName);
    final url = getLogoUrl(themeFolder, systemFolderName);
    return (await fetchAndCacheAsset(url, localPath)).path;
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
      if (!await _backgroundCached(themeFolder, system)) {
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

  /// Sentinel recording that the one-time cleanup of legacy `.missing` markers
  /// has already run for this install. Lives in the theme cache root, so
  /// wiping the cache (which re-downloads everything anyway) resets it.
  static Future<String> _markerCleanupSentinelPath() async {
    final dir = await _cacheDir();
    return path.join(dir, '.missing-markers-cleared');
  }

  /// Deletes every `.missing` marker left by older builds, once per install.
  ///
  /// The markers are no longer written or read: coverage now comes from the
  /// theme's declared `systems` list, so an uncovered system is never probed
  /// and needs no negative cache. Installs upgraded from an older build still
  /// carry the files, and a stale marker used to make a system's background
  /// read as "resolved" and stay permanently blank, so they are swept once.
  ///
  /// Called from [buildThemeDownloadPlan] rather than at startup: an install
  /// that never opens System Art pays nothing.
  static Future<void> deleteLegacyMissingMarkers() async {
    try {
      final sentinel = File(await _markerCleanupSentinelPath());
      if (await sentinel.exists()) return;

      final dir = Directory(await _cacheDir());
      int cleared = 0;
      if (await dir.exists()) {
        await for (final entity in dir.list(recursive: true)) {
          if (entity is File && entity.path.endsWith('.missing')) {
            await entity.delete();
            cleared++;
          }
        }
      }

      await sentinel.parent.create(recursive: true);
      await sentinel.writeAsString('');
      if (cleared > 0) {
        _log.i('Cleared $cleared legacy .missing marker(s) (no longer used)');
      }
    } catch (e) {
      _log.w('Error clearing legacy .missing markers: $e');
    }
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
