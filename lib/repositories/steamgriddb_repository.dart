import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Repository for the user's personal SteamGridDB API key.
///
/// Unlike ScreenScraper (shared dev credentials baked in at build time) or
/// RomM/NeoSync (a server login), SteamGridDB authenticates with a single
/// free personal API key the user generates themselves at
/// steamgriddb.com/profile/preferences/api — so there's nothing to store but
/// the key itself.
class SteamGridDbRepository {
  static const String _apiKeyStorageKey = 'steamgriddb_api_key';

  // Mirrors RetroAchievementsRepository's storage options: a transient
  // Android Keystore error must not silently erase the key.
  static const FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false, migrateWithBackup: true),
    mOptions: MacOsOptions(usesDataProtectionKeychain: false),
  );

  /// Persists the SteamGridDB API key securely.
  static Future<void> saveApiKey(String apiKey) async {
    await _storage.write(key: _apiKeyStorageKey, value: apiKey);
  }

  /// Returns the persisted API key, or null if not set.
  static Future<String?> getApiKey() async {
    final value = await _storage.read(key: _apiKeyStorageKey);
    return (value != null && value.isNotEmpty) ? value : null;
  }

  /// Clears the stored API key.
  static Future<void> clearApiKey() async {
    await _storage.delete(key: _apiKeyStorageKey);
  }
}
