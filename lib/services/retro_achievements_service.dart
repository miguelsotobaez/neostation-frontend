import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:neostation/services/logger_service.dart';
import '../models/retro_achievements_user.dart';
import '../models/retro_achievements_summary.dart';
import '../models/retro_achievements_game_info.dart';
import '../models/retro_achievements_gotw.dart';
import '../models/retro_achievement_comment.dart';
import '../models/retro_achievements_dashboard_models.dart';

/// Service for interacting with the RetroAchievements API.
///
/// Provides access to user profiles, game achievements, and global community
/// events like "Achievement of the Week". Every request is authenticated with
/// the *user's own* RetroAchievements web API key, supplied at connect time.
///
/// There is deliberately no build-time/environment fallback key: earlier
/// versions silently authenticated every user's traffic with the maintainer's
/// key, which is incorrect. A caller that passes no key gets an empty string
/// and the request-level guards reject it.
class RetroAchievementsService {
  static const String _baseUrl = 'https://retroachievements.org/API';

  /// Returns the trimmed [apiKey], or an empty string if none was supplied.
  /// Callers must pass the signed-in user's key; there is no shared fallback.
  static String resolveApiKey(String? apiKey) => apiKey?.trim() ?? '';

  static final _log = LoggerService.instance;

  /// Fetches the "Achievement of the Week" (GOTW) data.
  ///
  /// Optionally takes a [username] to include user-specific progress toward the achievement.
  static Future<RetroAchievementsGOTW?> getAchievementOfTheWeek({
    String? username,
    String? apiKey,
  }) async {
    final effectiveApiKey = resolveApiKey(apiKey);
    if (effectiveApiKey.isEmpty) {
      throw StateError('A RetroAchievements API key is required');
    }

    final url = Uri.parse(
      '$_baseUrl/API_GetAchievementOfTheWeek.php',
    ).replace(queryParameters: {'y': effectiveApiKey});

    final response = await http.get(
      url,
      headers: {'User-Agent': 'NeoStation/1.0', 'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw HttpException(
        'RetroAchievements achievement of the week request failed (${response.statusCode})',
      );
    }

    final data = json.decode(response.body);
    if (data != null && data['Achievement'] != null) {
      return RetroAchievementsGOTW.fromJson(data);
    }
    if (data != null && data['Error'] != null) {
      _log.e('API Error: ${data['Error']}');
    }
    return null;
  }

  /// Mapping of NeoStation system identifiers to RetroAchievements console IDs.
  static const Map<String, int> _systemMapping = {
    'nes': 7,
    'snes': 3,
    'gb': 4,
    'gbc': 6,
    'gba': 5,
    'n64': 2,
    'gcn': 16,
    'wii': 82,
    'nds': 18,
    '3ds': 78,
    'genesis': 1,
    'sms': 11,
    'gg': 15,
    'saturn': 39,
    'dreamcast': 40,
    'psx': 12,
    'ps2': 21,
    'psp': 41,
    'atari2600': 25,
    'atari7800': 51,
    'lynx': 13,
    'neogeo': 56,
    'arcade': 27,
    'msx': 29,
  };

  /// Returns the RetroAchievements console ID for a given NeoStation system name.
  static int? getConsoleIdForSystem(String systemFolderName) {
    return _systemMapping[systemFolderName.toLowerCase()];
  }

  /// Retrieves basic profile information for a RetroAchievements user.
  static Future<RetroAchievementsUser?> getUserProfile(
    String username, {
    String? apiKey,
  }) async {
    try {
      final url = Uri.parse(
        '$_baseUrl/API_GetUserProfile.php',
      ).replace(queryParameters: {'u': username, 'y': resolveApiKey(apiKey)});

      final response = await http.get(
        url,
        headers: {'User-Agent': 'NeoStation/1.0', 'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['User'] != null) {
          return RetroAchievementsUser.fromJson(data);
        } else {
          _log.e('User not found: $username');
          return null;
        }
      } else {
        _log.e('HTTP error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      _log.e('Error getting user profile: $e');
      return null;
    }
  }

  /// Checks if a username is registered on RetroAchievements.
  static Future<bool> userExists(String username, {String? apiKey}) async {
    final user = await getUserProfile(username, apiKey: apiKey);
    return user != null;
  }

  /// Fetches a comprehensive summary for a user, including recent games and achievements.
  ///
  /// Employs a cache-busting timestamp to ensure fresh data.
  static Future<RetroAchievementsUserSummary?> getUserSummary(
    String username, {
    String? apiKey,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final url = Uri.parse('$_baseUrl/API_GetUserSummary.php').replace(
        queryParameters: {
          'u': username,
          'g': '1', // Include recent games
          'a': '2', // Include recent achievements
          'y': resolveApiKey(apiKey),
          '_t': timestamp.toString(),
        },
      );

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'NeoStation/1.0',
          'Accept': 'application/json',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data is Map && data['User'] != null) {
          return RetroAchievementsUserSummary.fromJson(
            data as Map<String, dynamic>,
          );
        } else if (data is List) {
          if (data.isNotEmpty && data.first is Map) {
            final userData = data.first as Map<String, dynamic>;
            if (userData['User'] != null) {
              return RetroAchievementsUserSummary.fromJson(userData);
            }
          }
          _log.e('Unexpected response: list without valid data');
          return null;
        } else {
          _log.e('User not found or invalid response: $username');
          return null;
        }
      } else {
        _log.e('HTTP error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      _log.e('Error getting user summary: $e');
      return null;
    }
  }

  /// Retrieves detailed information for a specific game and the user's progress.
  ///
  /// Can take an [md5Hash] for more accurate game identification within the RA database.
  static Future<GameInfoAndUserProgress?> getGameInfoAndUserProgress(
    int gameId,
    String username, {
    String? md5Hash,
    String? apiKey,
  }) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final queryParams = {
        'g': gameId.toString(),
        'u': username,
        'y': resolveApiKey(apiKey),
        'a': '1', // Include achievements
        '_t': timestamp.toString(),
      };

      final url = Uri.parse(
        '$_baseUrl/API_GetGameInfoAndUserProgress.php',
      ).replace(queryParameters: queryParams);

      final response = await http.get(
        url,
        headers: {
          'User-Agent': 'NeoStation/1.0',
          'Accept': 'application/json',
          'Cache-Control': 'no-cache, no-store, must-revalidate',
          'Pragma': 'no-cache',
          'Expires': '0',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['ID'] != null) {
          return GameInfoAndUserProgress.fromJson(data);
        } else {
          _log.e('Game not found: $gameId');
          return null;
        }
      } else {
        _log.e('HTTP error ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      _log.e('Error getting game information: $e');
      return null;
    }
  }

  /// Retrieves newest-first comments from an achievement's RA page.
  static Future<RetroAchievementCommentsPage> getAchievementComments(
    int achievementId, {
    int count = 25,
    int offset = 0,
    String? apiKey,
    http.Client? client,
  }) async {
    final effectiveApiKey = resolveApiKey(apiKey);
    if (effectiveApiKey.isEmpty) {
      throw StateError('A RetroAchievements API key is required');
    }

    final url = Uri.parse('$_baseUrl/API_GetComments.php').replace(
      queryParameters: {
        't': '2',
        'i': achievementId.toString(),
        'c': count.clamp(1, 500).toString(),
        'o': offset.clamp(0, 1 << 31).toString(),
        'sort': '-submitted',
        'y': effectiveApiKey,
      },
    );
    final headers = {
      'User-Agent': 'NeoStation/1.0',
      'Accept': 'application/json',
    };
    final response = client == null
        ? await http.get(url, headers: headers)
        : await client.get(url, headers: headers);
    if (response.statusCode != 200) {
      throw HttpException(
        'RetroAchievements comments request failed (${response.statusCode})',
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map) {
      throw const FormatException(
        'Invalid RetroAchievements comments response',
      );
    }
    return RetroAchievementCommentsPage.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  /// Resolves a game's information and user progress using a file hash.
  @Deprecated(
    'The Web API does not support hash lookup on the user-progress endpoint. '
    'Resolve the hash to a game ID locally, then call getGameInfoAndUserProgress.',
  )
  static Future<GameInfoAndUserProgress?> searchGameByHash(
    String md5Hash,
    String username, {
    String? apiKey,
  }) async {
    _log.w(
      'Ignoring unsupported RA hash-only lookup for $md5Hash. '
      'Resolve a game ID from the local hash database first.',
    );
    return null;
  }

  static const String apiGetUserAwards = 'API_GetUserAwards.php';

  static Future<List<RetroAchievementRecentUnlockItem>>
  getUserRecentAchievements(
    String username, {
    int minutes = 43200,
    String? apiKey,
    http.Client? client,
  }) async {
    final url = Uri.parse('$_baseUrl/API_GetUserRecentAchievements.php')
        .replace(
          queryParameters: {
            'u': username,
            'm': minutes.toString(),
            'y': resolveApiKey(apiKey),
          },
        );

    final headers = {
      'User-Agent': 'NeoStation/1.0',
      'Accept': 'application/json',
    };
    final response = client == null
        ? await http.get(url, headers: headers)
        : await client.get(url, headers: headers);

    if (response.statusCode != 200) {
      throw HttpException(
        'RetroAchievements recent achievements request failed (${response.statusCode})',
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! List) {
      throw const FormatException(
        'Invalid RetroAchievements recent achievements response',
      );
    }

    return decoded
        .map(
          (item) => RetroAchievementRecentUnlockItem.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  static Future<List<RetroAchievementRecentlyPlayedGameItem>>
  getUserRecentlyPlayedGames(
    String username, {
    int count = 10,
    int offset = 0,
    String? apiKey,
    http.Client? client,
  }) async {
    final url = Uri.parse('$_baseUrl/API_GetUserRecentlyPlayedGames.php')
        .replace(
          queryParameters: {
            'u': username,
            'c': count.clamp(1, 50).toString(),
            'o': offset.clamp(0, 1 << 31).toString(),
            'y': resolveApiKey(apiKey),
          },
        );

    final headers = {
      'User-Agent': 'NeoStation/1.0',
      'Accept': 'application/json',
    };
    final response = client == null
        ? await http.get(url, headers: headers)
        : await client.get(url, headers: headers);

    if (response.statusCode != 200) {
      throw HttpException(
        'RetroAchievements recently played request failed (${response.statusCode})',
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! List) {
      throw const FormatException(
        'Invalid RetroAchievements recently played response',
      );
    }

    return decoded
        .map(
          (item) => RetroAchievementRecentlyPlayedGameItem.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
  }

  static Future<RetroAchievementCompletionProgressSummary>
  getUserCompletionProgress(
    String username, {
    int count = 100,
    int offset = 0,
    String? apiKey,
    http.Client? client,
  }) async {
    final url = Uri.parse('$_baseUrl/API_GetUserCompletionProgress.php')
        .replace(
          queryParameters: {
            'u': username,
            'c': count.clamp(1, 500).toString(),
            'o': offset.clamp(0, 1 << 31).toString(),
            'y': resolveApiKey(apiKey),
          },
        );

    final headers = {
      'User-Agent': 'NeoStation/1.0',
      'Accept': 'application/json',
    };
    final response = client == null
        ? await http.get(url, headers: headers)
        : await client.get(url, headers: headers);

    if (response.statusCode != 200) {
      throw HttpException(
        'RetroAchievements completion progress request failed (${response.statusCode})',
      );
    }

    final decoded = json.decode(response.body);
    if (decoded is! Map) {
      throw const FormatException(
        'Invalid RetroAchievements completion progress response',
      );
    }

    return RetroAchievementCompletionProgressSummary.fromJson(
      Map<String, dynamic>.from(decoded),
    );
  }

  /// Retrieves the list of site-wide awards earned by a user.
  static Future<Map<String, dynamic>?> getUserAwards(
    String username, {
    String? apiKey,
  }) async {
    final effectiveApiKey = resolveApiKey(apiKey);
    if (effectiveApiKey.isEmpty) {
      throw StateError('A RetroAchievements API key is required');
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final url = Uri.parse('$_baseUrl/$apiGetUserAwards').replace(
      queryParameters: {
        'u': username,
        'y': effectiveApiKey,
        '_t': timestamp.toString(),
      },
    );

    final response = await http.get(
      url,
      headers: {
        'User-Agent': 'NeoStation/1.0',
        'Accept': 'application/json',
        'Cache-Control': 'no-cache, no-store, must-revalidate',
        'Pragma': 'no-cache',
        'Expires': '0',
      },
    );

    if (response.statusCode != 200) {
      throw HttpException(
        'RetroAchievements user awards request failed (${response.statusCode})',
      );
    }

    final data = json.decode(response.body);
    return data as Map<String, dynamic>;
  }

  /// Searches for games by name within a specific console category.
  ///
  /// Performs normalized string matching (removing special characters and
  /// excessive whitespace) to improve discovery.
  static Future<List<Map<String, dynamic>>> searchGamesByName(
    String gameName,
    int consoleId, {
    String? apiKey,
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/API_GetGameList.php').replace(
        queryParameters: {
          'i': consoleId.toString(),
          'y': resolveApiKey(apiKey),
        },
      );

      final response = await http.get(
        url,
        headers: {'User-Agent': 'NeoStation/1.0', 'Accept': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data is List) {
          final normalizedSearchName = gameName
              .toLowerCase()
              .replaceAll(RegExp(r'[^\w\s]'), '')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();

          final matches = <Map<String, dynamic>>[];

          for (final game in data) {
            final gameTitle = game['Title']?.toString() ?? '';
            final normalizedGameTitle = gameTitle
                .toLowerCase()
                .replaceAll(RegExp(r'[^\w\s]'), '')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();

            if (normalizedGameTitle == normalizedSearchName ||
                normalizedGameTitle.contains(normalizedSearchName) ||
                normalizedSearchName.contains(normalizedGameTitle)) {
              matches.add(game);
            }
          }

          return matches;
        }
      } else {
        _log.e('HTTP error ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      _log.e('Error searching games: $e');
    }

    return [];
  }
}
