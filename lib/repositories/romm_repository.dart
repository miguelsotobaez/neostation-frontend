import 'dart:convert';

import '../data/datasources/sqlite_service.dart';
import 'package:neostation/services/logger_service.dart';

/// Repository for RomM server credentials and tokens (single-row config).
///
/// Per the architecture rules, this is the only layer that touches
/// [SqliteService] for RomM data access. The password and the API key are
/// stored base64-encoded (matching the ScreenScraper integration); this is
/// obfuscation, not strong encryption.
class RommRepository {
  static final _log = LoggerService.instance;

  /// Persists the server URL and credentials. Tokens are cleared whenever the
  /// credentials change so a fresh authentication is forced.
  ///
  /// The two authentication modes are mutually exclusive: pass either
  /// [username]/[password] or [apiKey]. Whichever is left empty is written as
  /// empty, so switching a connection from one mode to the other never leaves
  /// the previous mode's secret behind to be picked up on the next launch.
  static Future<bool> saveConfig({
    required String serverUrl,
    String username = '',
    String password = '',
    String apiKey = '',
  }) async {
    try {
      final db = await SqliteService.getDatabase();

      await db.insert('user_romm_config', {
        'id': 1,
        'server_url': serverUrl,
        'username': username,
        'password': _encodeSecret(password),
        'api_key': _encodeSecret(apiKey),
        'access_token': null,
        'refresh_token': null,
        'token_expires': null,
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      return true;
    } catch (e) {
      _log.e('Error saving RomM config: $e');
      return false;
    }
  }

  /// Returns the stored config with the secrets decoded, or null if none.
  ///
  /// Keys: `server_url`, `username`, `password`, `api_key`, `access_token`,
  /// `refresh_token`, `token_expires` (int millis since epoch, nullable),
  /// `last_verified`. A non-empty `api_key` means the connection authenticates
  /// with a Client API Token rather than the password grant.
  static Future<Map<String, dynamic>?> getConfig() async {
    try {
      final db = await SqliteService.getDatabase();
      final result = await db.query('user_romm_config');
      if (result.isEmpty) return null;

      final row = result.first;
      final serverUrl = row['server_url']?.toString();
      if (serverUrl == null || serverUrl.isEmpty) return null;

      return {
        'server_url': serverUrl,
        'username': row['username']?.toString() ?? '',
        'password': _decodeSecret(row['password']),
        'api_key': _decodeSecret(row['api_key']),
        'access_token': row['access_token']?.toString(),
        'refresh_token': row['refresh_token']?.toString(),
        'token_expires': int.tryParse(row['token_expires']?.toString() ?? ''),
        'last_verified': row['last_verified']?.toString(),
      };
    } catch (e) {
      _log.e('Error getting RomM config: $e');
      return null;
    }
  }

  /// Base64-encodes a secret for storage; an empty secret stays empty so the
  /// "is this mode in use?" check is a plain `isNotEmpty` on the way back out.
  static String _encodeSecret(String value) =>
      value.isEmpty ? '' : base64Encode(utf8.encode(value));

  /// Inverse of [_encodeSecret], tolerating a null/absent column and any value
  /// that isn't valid base64 (both read back as "not set").
  static String _decodeSecret(Object? stored) {
    final encoded = stored?.toString();
    if (encoded == null || encoded.isEmpty) return '';
    try {
      return utf8.decode(base64Decode(encoded));
    } catch (_) {
      return '';
    }
  }

  /// Updates the cached JWT tokens after a successful authentication.
  ///
  /// [tokenExpires] is millis-since-epoch when the access token expires.
  static Future<bool> saveTokens({
    required String accessToken,
    String? refreshToken,
    int? tokenExpires,
  }) async {
    try {
      final db = await SqliteService.getDatabase();
      await db.update(
        'user_romm_config',
        {
          'access_token': accessToken,
          'refresh_token': ?refreshToken,
          'token_expires': tokenExpires,
          'last_verified': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [1],
      );
      return true;
    } catch (e) {
      _log.e('Error saving RomM tokens: $e');
      return false;
    }
  }

  /// Removes all stored RomM configuration (used on disconnect).
  static Future<bool> clearConfig() async {
    try {
      final db = await SqliteService.getDatabase();
      await db.delete('user_romm_config');
      return true;
    } catch (e) {
      _log.e('Error clearing RomM config: $e');
      return false;
    }
  }
}
