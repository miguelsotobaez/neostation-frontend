import 'package:flutter/foundation.dart';
import '../services/neo_assets_service.dart';
import '../repositories/config_repository.dart';
import '../services/logger_service.dart';

final _log = LoggerService.instance;

/// Provider responsible for managing remote and local theme assets (logos, backgrounds).
///
/// Handles theme discovery, batch downloading of assets, and persistence of the
/// active theme selection. Uses [NeoAssetsService] for network and cache I/O.
class NeoAssetsProvider extends ChangeNotifier {
  /// List of available themes fetched from the remote repository.
  List<NeoAssetsTheme> _themes = [];

  /// Folder name of the currently selected theme.
  String _activeThemeFolder = '';

  /// Whether a network request to fetch themes is in progress.
  bool _loading = false;

  /// Whether a background download of theme assets is active.
  bool _downloading = false;

  /// Normalized download progress (0.0 to 1.0).
  double _downloadProgress = 0.0;

  /// Internal flag to ensure initialization logic runs only once.
  bool _initialized = false;

  List<NeoAssetsTheme> get themes => _themes;
  String get activeThemeFolder => _activeThemeFolder;
  bool get loading => _loading;
  bool get downloading => _downloading;
  double get downloadProgress => _downloadProgress;
  bool get hasActiveTheme => _activeThemeFolder.isNotEmpty;

  /// Returns the currently active [NeoAssetsTheme] metadata.
  NeoAssetsTheme? get activeTheme => _themes.isEmpty
      ? null
      : _themes.where((t) => t.folder == _activeThemeFolder).firstOrNull;

  /// Initializes the theme cache directory and loads the active theme from the database.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await NeoAssetsService.ensureCacheDirInitialized();
    _activeThemeFolder = await ConfigRepository.getActiveTheme();
    notifyListeners();
    await loadThemes();
  }

  /// Re-runs [init] against the *current* user-data location.
  ///
  /// The setup wizard's first step can move the user data after this provider
  /// has already initialised, which leaves the cache directory and the active
  /// theme resolved against the folder the app started in. Calling this once
  /// the database has been reopened at the new path re-derives both.
  Future<void> reinitialize() async {
    _initialized = false;
    await init();
  }

  /// Fetches the list of available themes from the remote server.
  Future<void> loadThemes() async {
    _loading = true;
    notifyListeners();
    try {
      _themes = await NeoAssetsService.fetchThemes();
    } catch (e) {
      _log.e('Error loading themes: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Sets a new active theme and persists the choice to the local database.
  Future<void> setActiveTheme(String themeFolder) async {
    if (_activeThemeFolder == themeFolder) return;
    _activeThemeFolder = themeFolder;
    await ConfigRepository.updateActiveTheme(themeFolder);
    notifyListeners();
  }

  /// Deselects the current theme and resets the active selection.
  Future<void> clearTheme() async {
    _activeThemeFolder = '';
    await ConfigRepository.updateActiveTheme('');
    notifyListeners();
  }

  /// Downloads all required assets for the specified theme and applies it.
  ///
  /// Calculates a download plan to identify missing or outdated assets and
  /// performs a batch download with real-time progress updates. Returns whether
  /// the pack was actually applied, so a caller that reports success (the setup
  /// wizard) doesn't claim a pack the user has no art for.
  Future<bool> downloadAndApplyTheme(
    String themeFolder,
    List<String> systemFolderNames, {
    bool forceRedownload = false,
  }) async {
    try {
      final plan = await NeoAssetsService.buildThemeDownloadPlan(
        themeFolder,
        systemFolderNames,
      );

      // A forced redownload wipes the cache before refetching, so only honour
      // it once the theme metadata has actually come back: deleting art we
      // then cannot re-fetch (offline, CDN down) would leave the user with
      // none at all, which is worse than the missing background they asked us
      // to repair.
      final forced = forceRedownload && plan.remoteMetadata != null;
      if (forceRedownload && !forced) {
        _log.w(
          'Skipping forced redownload of "$themeFolder": '
          'theme metadata unreachable, keeping the cached art',
        );
      }

      // Nothing the pack declares matched anything installed — which on a first
      // apply means the theme metadata never arrived (a dropped request leaves
      // `systems` unknown, and an unknown list covers nothing). Marking the
      // pack active here is how a theme comes to read as applied with not one
      // background on disk: no later launch re-plans it, so the art never
      // appears until the user re-picks the pack by hand.
      if (plan.systemsToDownload.isEmpty) {
        _log.w(
          'Not applying theme "$themeFolder": the download plan covers no '
          'systems (metadata unreachable, or the pack covers none of the '
          '${systemFolderNames.length} installed systems)',
        );
        return false;
      }

      final clearFirst = forced || plan.forceRedownload;
      final totalAssets = clearFirst
          ? plan.systemsToDownload.length
          : plan.totalAssetsToDownload;

      if (totalAssets > 0) {
        _downloading = true;
        _downloadProgress = 0.0;
        notifyListeners();

        if (clearFirst) {
          await NeoAssetsService.downloadAllThemeAssets(
            themeFolder,
            plan.systemsToDownload,
            forceRedownload: true,
            onProgress: (done, t) {
              _downloadProgress = t == 0 ? 1.0 : done / t;
              notifyListeners();
            },
          );
        } else {
          await NeoAssetsService.downloadMissingThemeAssets(
            themeFolder,
            plan.systemsToDownload,
            missingTotal: totalAssets,
            onProgress: (done, t) {
              _downloadProgress = t == 0 ? 1.0 : done / t;
              notifyListeners();
            },
          );
        }
      }

      if (plan.remoteMetadata != null) {
        await NeoAssetsService.writeLocalThemeMetadata(
          themeFolder,
          plan.remoteMetadata!,
        );
      }

      _activeThemeFolder = themeFolder;
      await ConfigRepository.updateActiveTheme(themeFolder);
      return true;
    } catch (e) {
      _log.e('Error downloading theme: $e');
      return false;
    } finally {
      _downloading = false;
      _downloadProgress = 0.0;
      notifyListeners();
    }
  }

  /// Resolves the absolute path to a system background within the active theme.
  Future<String?> getBackgroundForSystem(String systemFolderName) async {
    if (!hasActiveTheme) return null;
    return NeoAssetsService.getCachedBackground(
      _activeThemeFolder,
      systemFolderName,
    );
  }

  /// Synchronous variant for resolving background paths.
  /// Checks the cache for both .webp and .gif formats.
  String? getBackgroundForSystemSync(String systemFolderName) {
    if (!hasActiveTheme) return null;
    return NeoAssetsService.resolveBackgroundPathSync(
      _activeThemeFolder,
      systemFolderName,
    );
  }

  /// Logos are no longer loaded from remote themes.
  /// Returns null to fall through to bundled local assets.
  Future<String?> getLogoForSystem(String systemFolderName) async {
    return null;
  }

  /// Synchronous variant — always returns null.
  String? getLogoForSystemSync(String systemFolderName) {
    return null;
  }
}
