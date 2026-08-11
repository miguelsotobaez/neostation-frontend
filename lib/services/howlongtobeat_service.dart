import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import '../repositories/scraper_repository.dart';
import 'package:neostation/providers/sqlite_database_provider.dart';
import 'package:neostation/services/logger_service.dart';

/// Service responsible for fetching completion-time estimates from
/// HowLongToBeat (howlongtobeat.com).
///
/// HowLongToBeat has no official public API; this mirrors the request shape
/// used by the community `howlongtobeat` libraries (ckatzorke/howlongtobeat)
/// against the site's own search endpoint — a plain POST with a browser-like
/// User-Agent/Origin/Referer, no key required. If HowLongToBeat changes that
/// endpoint or starts rejecting these headers, requests will start failing
/// with a non-200 status and scraping simply finds nothing new; nothing else
/// in the app depends on this succeeding.
class HowLongToBeatService {
  static const String _searchUrl = 'https://howlongtobeat.com/api/search';

  static final _log = LoggerService.instance;

  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Origin': 'https://howlongtobeat.com',
    'Referer': 'https://howlongtobeat.com/',
  };

  static Map<String, dynamic> _payload(String query) => {
    'searchType': 'games',
    'searchTerms': query.split(' '),
    'searchPage': 1,
    'size': 20,
    'searchOptions': {
      'games': {
        'userId': 0,
        'platform': '',
        'sortCategory': 'popular',
        'rangeCategory': 'main',
        'rangeTime': {'min': 0, 'max': 0},
        'gameplay': {'perspective': '', 'flow': '', 'genre': ''},
        'modifier': '',
      },
      'users': {'sortCategory': 'postcount'},
      'filter': '',
      'sort': 0,
      'randomizer': 0,
    },
  };

  /// Performs a batch scrape across every ROM on every detected system,
  /// filling in completion-time estimates for games that haven't been looked
  /// up yet. [onProgress] reports (processed, total) after each ROM.
  static Future<int> scrapeAll({
    SqliteDatabaseProvider? provider,
    void Function(int processed, int total)? onProgress,
  }) async {
    final roms = await ScraperRepository.getAllRomsForArtworkScraping();
    int scrapeCount = 0;
    final touchedSystems = <String>{};

    for (var i = 0; i < roms.length; i++) {
      final rom = roms[i];
      final filename = rom['filename'].toString();
      final appSystemId = rom['app_system_id'].toString();
      final systemFolder = rom['folder_name'].toString();
      final title = (rom['title_name']?.toString().trim().isNotEmpty ?? false)
          ? rom['title_name'].toString()
          : path.basenameWithoutExtension(filename);

      final existing = await ScraperRepository.getHltbForGame(
        appSystemId,
        filename,
      );
      if (existing == null) {
        final found = await _scrapeSingleGame(appSystemId, filename, title);
        if (found) {
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

    _log.i('HowLongToBeat: scraped estimates for $scrapeCount game(s).');
    return scrapeCount;
  }

  /// Looks up [title] and persists the best match's completion times.
  /// Always writes a row (even all-null) so a game with no HLTB match isn't
  /// re-queried on every subsequent scrape run. Returns true only when at
  /// least one hour value was found.
  static Future<bool> _scrapeSingleGame(
    String appSystemId,
    String filename,
    String title,
  ) async {
    try {
      final match = await _search(title);
      await ScraperRepository.upsertHltbMetadata(
        appSystemId: appSystemId,
        filename: filename,
        mainHours: match?.mainHours,
        mainExtraHours: match?.mainExtraHours,
        completionistHours: match?.completionistHours,
      );
      return match != null;
    } catch (e) {
      _log.e('HowLongToBeat: error processing "$title"', error: e);
      return false;
    }
  }

  /// Searches for [title] and returns the closest-named result, or null.
  static Future<_HltbMatch?> _search(String title) async {
    final response = await http.post(
      Uri.parse(_searchUrl),
      headers: _headers,
      body: json.encode(_payload(title)),
    );
    if (response.statusCode != 200) {
      _log.w('HowLongToBeat: search failed (${response.statusCode})');
      return null;
    }

    final body = json.decode(response.body);
    final results = body['data'] as List?;
    if (results == null || results.isEmpty) return null;

    // The API doesn't rank by name similarity, so pick the entry whose name
    // is closest to the query (a bare Levenshtein-free heuristic: exact
    // case-insensitive match first, then "starts with", then first result).
    final lowerTitle = title.toLowerCase().trim();
    Map<String, dynamic>? best;
    for (final entry in results.cast<Map<String, dynamic>>()) {
      final name = (entry['game_name'] ?? '').toString().toLowerCase().trim();
      if (name == lowerTitle) {
        best = entry;
        break;
      }
      if (best == null && name.startsWith(lowerTitle)) {
        best = entry;
      }
    }
    best ??= results.first as Map<String, dynamic>;

    int? secondsToHours(dynamic seconds) {
      final value = (seconds as num?)?.toInt();
      if (value == null || value <= 0) return null;
      return (value / 3600).round();
    }

    return _HltbMatch(
      mainHours: secondsToHours(best['comp_main']),
      mainExtraHours: secondsToHours(best['comp_plus']),
      completionistHours: secondsToHours(best['comp_100']),
    );
  }
}

class _HltbMatch {
  final int? mainHours;
  final int? mainExtraHours;
  final int? completionistHours;

  const _HltbMatch({
    this.mainHours,
    this.mainExtraHours,
    this.completionistHours,
  });
}
