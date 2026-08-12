import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../repositories/system_repository.dart';
import '../repositories/scraper_repository.dart';
import 'package:neostation/services/config_service.dart';
import 'package:neostation/providers/sqlite_database_provider.dart';
import 'package:neostation/services/logger_service.dart';

/// Service responsible for fetching metadata and media from the Steam Store API.
///
/// Integrates with the application's persistence layer to enrich Steam game entries
/// with descriptions, ratings, and localized media (fanarts, logos, screenshots).
class SteamScraperService {
  /// Base URL for the Steam Storefront API app details endpoint.
  static const String _steamApiUrl =
      'https://store.steampowered.com/api/appdetails';

  static final _log = LoggerService.instance;

  /// Performs a batch scraping operation for all registered Steam games.
  ///
  /// Targets entries that have a valid Steam App ID but are missing localized
  /// metadata or physical media assets on disk.
  static Future<void> scrapeSteamGames({
    SqliteDatabaseProvider? provider,
  }) async {
    try {
      // 1. Resolve the logical Steam system to obtain its internal ID.
      final steamSystem = await SystemRepository.getSystemByFolderName('steam');
      if (steamSystem?.id == null) return;

      // 2. Identify candidates for metadata enrichment.
      // We fetch games that possess a 'title_id' (Steam App ID) and verify their completion status.
      final allGames = await ScraperRepository.getSteamGamesWithScrapeStatus(
        steamSystem!.id!,
      );

      // 3. Resolve user language preferences for API localization.
      final lang = await _getPreferredLanguage();

      // 4. Sequential processing of game metadata.
      int scrapeCount = 0;
      for (final game in allGames) {
        final filename = game['filename'].toString();
        final romPath = game['rom_path'].toString();
        final appId = game['title_id'].toString();
        final isFullyScraped =
            (int.tryParse(game['is_fully_scraped']?.toString() ?? '0') ?? 0) ==
            1;

        // Perform a physical integrity check for media assets.
        final bool missingImages = await _needsImages('steam', filename);

        if (!isFullyScraped || missingImages) {
          scrapeCount++;
          await _scrapeSingleGame(
            steamSystem.id!,
            filename,
            romPath,
            appId,
            lang,
          );

          // Trigger a reactive UI update if a state provider is attached.
          if (provider != null) {
            await provider.refreshSystem('steam');
          }
        }
      }

      if (scrapeCount > 0) {
        _log.i(
          'SteamScraper: Successfully synchronized $scrapeCount game entries.',
        );
      } else {
        _log.i('SteamScraper: Local metadata and media library is up to date.');
      }
    } catch (e) {
      _log.e('SteamScraper: Critical failure during batch operation', error: e);
    }
  }

  /// Synchronizes metadata for a specific Steam application ID.
  static Future<void> _scrapeSingleGame(
    String systemId,
    String filename,
    String romPath,
    String appId,
    String lang,
  ) async {
    try {
      final url = Uri.parse('$_steamApiUrl?appids=$appId&l=$lang');
      final response = await http.get(url);

      if (response.statusCode != 200) {
        _log.e(
          'SteamScraper: API upstream error (Status: ${response.statusCode})',
        );
        return;
      }

      final data = json.decode(response.body);
      if (data[appId] == null || data[appId]['success'] != true) {
        _log.w('SteamScraper: No valid data payload for AppID $appId');
        return;
      }

      final gameData = data[appId]['data'];

      // Map Steam API response to application metadata schema.
      final metadata = <String, dynamic>{
        'app_system_id': systemId,
        'filename': filename,
        'real_name': gameData['name'] ?? filename,
        'developer': (gameData['developers'] as List?)?.first?.toString(),
        'publisher': (gameData['publishers'] as List?)?.first?.toString(),
        'rating':
            (gameData['metacritic']?['score'] as num? ?? 0) /
            5.0, // Normalize metacritic 0-100 to 0-20 (UI maps to 0-10 star scale).
        'release_date': gameData['release_date']?['date']?.toString(),
        'genre': (gameData['genres'] as List?)?.first?['description']
            ?.toString(),
        'is_fully_scraped': 1,
        'updated_at': DateTime.now().toIso8601String(),
      };

      // Localized description logic: persist in requested language with English fallback.
      final description = gameData['short_description']?.toString() ?? '';
      metadata['description_$lang'] = description;
      if (lang != 'en') {
        metadata['description_en'] = description;
      }

      // Upsert into the persistent storage.
      await ScraperRepository.upsertSteamMetadata(metadata);

      // Trigger asynchronous media download.
      await _downloadMedia(gameData, 'steam', filename, appId);
    } catch (e) {
      _log.e('SteamScraper: Error processing AppID $appId', error: e);
    }
  }

  /// Orchestrates the download of media assets based on Steam API URLs.
  static Future<void> _downloadMedia(
    Map<String, dynamic> gameData,
    String systemFolder,
    String filename,
    String appId,
  ) async {
    final mediaDir = await ConfigService.getMediaPath();

    // Standardize filename by stripping extension for media filesystem matching.
    final String romBaseName = filename.contains('.')
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;

    // Steam API Mapping to NeoStation Media Convention:
    // - Static URL based on AppID -> fanarts/ (Background art)
    // - Static URL based on AppID -> box2D/ (Box art)
    // - Static URL based on AppID -> wheels/ (Transparent Logo)
    // - screenshots[0] -> screenshots/ (In-game thumbnail)

    final fanartUrl =
        'https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/$appId/library_hero.jpg';
    final box2dUrl =
        'https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/$appId/library_600x900.jpg';
    final wheelUrl =
        'https://shared.fastly.steamstatic.com/store_item_assets/steam/apps/$appId/logo.png';
    final ssUrl = (gameData['screenshots'] as List?)?.first?['path_thumbnail']
        ?.toString();

    await _downloadFile(
      fanartUrl,
      path.join(mediaDir, systemFolder, 'fanarts', '$romBaseName.jpg'),
    );

    await _downloadFile(
      box2dUrl,
      path.join(mediaDir, systemFolder, 'box2D', '$romBaseName.jpg'),
    );

    // Standardize logos to PNG format; perform cleanup of legacy JPG assets.
    final oldJpgWheel = File(
      path.join(mediaDir, systemFolder, 'wheels', '$romBaseName.jpg'),
    );
    if (await oldJpgWheel.exists()) {
      try {
        await oldJpgWheel.delete();
      } catch (e) {
        _log.w(
          'SteamScraper: Failed to purge legacy JPG wheel asset, error: $e',
        );
      }
    }

    await _downloadFile(
      wheelUrl,
      path.join(mediaDir, systemFolder, 'wheels', '$romBaseName.png'),
    );

    if (ssUrl != null) {
      await _downloadFile(
        ssUrl,
        path.join(mediaDir, systemFolder, 'screenshots', '$romBaseName.jpg'),
      );
    } else {
      _log.w('SteamScraper: Screenshot URL missing for $romBaseName');
    }
  }

  /// Downloads a remote file to the local filesystem if it doesn't already exist.
  static Future<void> _downloadFile(String url, String savePath) async {
    try {
      final file = File(savePath);

      // Avoid redundant network requests if asset is already localized.
      if (await file.exists()) return;

      await file.parent.create(recursive: true);
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
      }
    } catch (e) {
      _log.e('SteamScraper: Network failure downloading $url', error: e);
    }
  }

  /// Determines if the local media library for a game is incomplete.
  static Future<bool> _needsImages(String systemFolder, String filename) async {
    final mediaDir = await ConfigService.getMediaPath();

    final String romBaseName = filename.contains('.')
        ? filename.substring(0, filename.lastIndexOf('.'))
        : filename;

    // Define the core media requirements for a 'complete' entry.
    final imageConfigs = [
      {'folder': 'fanarts', 'ext': 'jpg'},
      {'folder': 'box2D', 'ext': 'jpg'},
      {'folder': 'wheels', 'ext': 'png'},
      {'folder': 'screenshots', 'ext': 'jpg'},
    ];

    for (final config in imageConfigs) {
      final folder = config['folder']!;
      final ext = config['ext']!;
      final imagePath = path.join(
        mediaDir,
        systemFolder,
        folder,
        '$romBaseName.$ext',
      );

      if (!await File(imagePath).exists()) {
        _log.d(
          'SteamScraper: Missing required $folder asset ($ext) for $romBaseName',
        );
        return true;
      }
    }
    return false;
  }

  /// Retrieves the preferred language for scraper operations from local configuration.
  static Future<String> _getPreferredLanguage() async {
    return ScraperRepository.getPreferredLanguage();
  }
}
