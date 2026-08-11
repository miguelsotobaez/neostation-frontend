import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../repositories/scraper_repository.dart';
import '../repositories/steamgriddb_repository.dart';
import 'package:neostation/services/config_service.dart';
import 'package:neostation/providers/sqlite_database_provider.dart';
import 'package:neostation/services/logger_service.dart';

/// Service responsible for fetching cover/background/logo artwork from
/// SteamGridDB (steamgriddb.com) — a community-curated art database, not tied
/// to Steam specifically (despite the name, most entries cover any game on
/// any platform).
///
/// SteamGridDB has no metadata (description, genre, rating) — it is an
/// artwork-only source, run independently of ScreenScraper rather than as a
/// replacement for it. Fills gaps only: an existing image on disk (from
/// ScreenScraper, Steam, or a previous SteamGridDB run) is never overwritten.
class SteamGridDbService {
  static const String _baseUrl = 'https://www.steamgriddb.com/api/v2';

  static final _log = LoggerService.instance;

  /// Performs a live lookup to confirm [apiKey] is accepted by the API.
  /// Used by the settings screen before saving a newly entered key.
  static Future<bool> validateApiKey(String apiKey) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/search/autocomplete/mario'),
        headers: {'Authorization': 'Bearer $apiKey'},
      );
      return response.statusCode == 200;
    } catch (e) {
      _log.e('SteamGridDB: API key validation failed', error: e);
      return false;
    }
  }

  /// Performs a batch scraping operation across every ROM on every detected
  /// system, filling in whichever of cover/fanart/logo art is missing on
  /// disk. [onProgress] reports (processed, total) after each ROM.
  static Future<int> scrapeAll({
    SqliteDatabaseProvider? provider,
    void Function(int processed, int total)? onProgress,
  }) async {
    final apiKey = await SteamGridDbRepository.getApiKey();
    if (apiKey == null) {
      _log.w('SteamGridDB: scrape requested with no API key configured');
      return 0;
    }

    final roms = await ScraperRepository.getAllRomsForArtworkScraping();
    int scrapeCount = 0;
    final touchedSystems = <String>{};

    for (var i = 0; i < roms.length; i++) {
      final rom = roms[i];
      final filename = rom['filename'].toString();
      final systemFolder = rom['folder_name'].toString();
      final title = (rom['title_name']?.toString().trim().isNotEmpty ?? false)
          ? rom['title_name'].toString()
          : path.basenameWithoutExtension(filename);

      final missing = await _missingArt(systemFolder, filename);
      if (missing.isNotEmpty) {
        final downloaded = await _scrapeSingleGame(
          apiKey,
          systemFolder,
          filename,
          title,
          missing,
        );
        if (downloaded) {
          scrapeCount++;
          touchedSystems.add(systemFolder);
        }
      }

      onProgress?.call(i + 1, roms.length);
    }

    if (provider != null) {
      for (final folder in touchedSystems) {
        await provider.refreshSystem(folder);
      }
    }

    _log.i('SteamGridDB: scraped artwork for $scrapeCount game(s).');
    return scrapeCount;
  }

  /// Resolves and downloads whichever of [missing] art kinds SteamGridDB has
  /// for [title]. Returns true if at least one file was written.
  static Future<bool> _scrapeSingleGame(
    String apiKey,
    String systemFolder,
    String filename,
    String title,
    Set<_ArtKind> missing,
  ) async {
    try {
      final gameId = await _searchGameId(apiKey, title);
      if (gameId == null) {
        _log.d('SteamGridDB: no match for "$title"');
        return false;
      }

      final romBaseName = path.basenameWithoutExtension(filename);
      final mediaDir = await ConfigService.getMediaPath();
      var wroteAny = false;

      for (final kind in missing) {
        final url = await _firstArtUrl(apiKey, gameId, kind);
        if (url == null) continue;
        final savePath = path.join(
          mediaDir,
          systemFolder,
          kind.mediaFolder,
          '$romBaseName${kind.extensionOf(url)}',
        );
        if (await _downloadFile(url, savePath)) wroteAny = true;
      }

      return wroteAny;
    } catch (e) {
      _log.e('SteamGridDB: error processing "$title"', error: e);
      return false;
    }
  }

  /// Autocomplete-searches for [title], returning the top match's game id.
  static Future<int?> _searchGameId(String apiKey, String title) async {
    final url = Uri.parse(
      '$_baseUrl/search/autocomplete/${Uri.encodeComponent(title)}',
    );
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $apiKey'},
    );
    if (response.statusCode != 200) return null;

    final body = json.decode(response.body);
    final results = body['data'] as List?;
    if (results == null || results.isEmpty) return null;
    return results.first['id'] as int?;
  }

  /// Returns the URL of the top-ranked asset of [kind] for [gameId], or null.
  static Future<String?> _firstArtUrl(
    String apiKey,
    int gameId,
    _ArtKind kind,
  ) async {
    final url = Uri.parse('$_baseUrl/${kind.endpoint}/game/$gameId');
    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $apiKey'},
    );
    if (response.statusCode != 200) return null;

    final body = json.decode(response.body);
    final results = body['data'] as List?;
    if (results == null || results.isEmpty) return null;
    return results.first['url']?.toString();
  }

  /// Which art kinds are missing on disk for this ROM — SteamGridDB only
  /// fills gaps, so a kind already present (from any source) is skipped.
  static Future<Set<_ArtKind>> _missingArt(
    String systemFolder,
    String filename,
  ) async {
    final mediaDir = await ConfigService.getMediaPath();
    final romBaseName = path.basenameWithoutExtension(filename);
    final missing = <_ArtKind>{};

    for (final kind in _ArtKind.values) {
      final dir = Directory(
        path.join(mediaDir, systemFolder, kind.mediaFolder),
      );
      final hasAny =
          dir.existsSync() &&
          dir.listSync().whereType<File>().any(
            (f) => path.basenameWithoutExtension(f.path) == romBaseName,
          );
      if (!hasAny) missing.add(kind);
    }
    return missing;
  }

  /// Downloads [url] to [savePath], creating parent directories as needed.
  /// Returns true on success.
  static Future<bool> _downloadFile(String url, String savePath) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return false;
      final file = File(savePath);
      await file.parent.create(recursive: true);
      await file.writeAsBytes(response.bodyBytes);
      return true;
    } catch (e) {
      _log.e('SteamGridDB: network failure downloading $url', error: e);
      return false;
    }
  }
}

/// An artwork kind SteamGridDB serves, mapped to NeoStation's media
/// filesystem convention (matching what [SteamScraperService] and
/// ScreenScraper both write to).
enum _ArtKind {
  grid('grids', 'box2D'),
  hero('heroes', 'fanarts'),
  logo('logos', 'wheels');

  const _ArtKind(this.endpoint, this.mediaFolder);

  /// SteamGridDB API path segment (`/grids`, `/heroes`, `/logos`).
  final String endpoint;

  /// NeoStation media subfolder this kind is saved under.
  final String mediaFolder;

  /// File extension to save under, taken from the asset URL itself —
  /// SteamGridDB serves a mix of PNG/JPG/WEBP per asset.
  String extensionOf(String url) {
    final ext = path.extension(Uri.parse(url).path);
    return ext.isNotEmpty ? ext : '.png';
  }
}
