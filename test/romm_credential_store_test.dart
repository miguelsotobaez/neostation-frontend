import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/repositories/romm_repository.dart';
import 'package:neostation/services/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_test_helper.dart';
import 'fake_credential_backends.dart';

/// Writes a row the way a pre-migration build (or the local dev seeder) does:
/// the secret base64-encoded straight into the column.
Future<void> seedLegacyRow({
  String serverUrl = 'https://romm.example',
  String username = 'neil',
  String password = '',
  String apiKey = '',
}) async {
  final db = await SqliteService.getDatabase();
  await db.insert('user_romm_config', {
    'id': 1,
    'server_url': serverUrl,
    'username': username,
    'password': password.isEmpty ? '' : base64Encode(utf8.encode(password)),
    'api_key': apiKey.isEmpty ? '' : base64Encode(utf8.encode(apiKey)),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<Map<String, Object?>> readRow() async {
  final db = await SqliteService.getDatabase();
  return (await db.query('user_romm_config')).first;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final dbHelper = DatabaseTestHelper();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await dbHelper.setUp();
  });

  tearDown(() async {
    CredentialStore.debugReset();
    await dbHelper.tearDown();
  });

  group('RommRepository secrets', () {
    test('saveConfig keeps the password out of the database', () async {
      final secure = MemoryBackend();
      CredentialStore.debugUseBackends(secure: secure, file: MemoryBackend());

      await RommRepository.saveConfig(
        serverUrl: 'https://romm.example',
        username: 'neil',
        password: 'hunter2',
      );

      expect(secure.values['romm_password'], 'hunter2');
      expect((await readRow())['password'], '');
      expect((await getConfigPassword()), 'hunter2');
    });

    test('saveConfig keeps the API key out of the database', () async {
      final secure = MemoryBackend();
      CredentialStore.debugUseBackends(secure: secure, file: MemoryBackend());

      await RommRepository.saveConfig(
        serverUrl: 'https://romm.example',
        apiKey: 'never-expires',
      );

      expect(secure.values['romm_api_key'], 'never-expires');
      expect((await readRow())['api_key'], '');

      final config = await RommRepository.getConfig();
      // A non-empty api_key is what marks the connection as API-key auth, so
      // the mode has to survive the move.
      expect(config!['api_key'], 'never-expires');
      expect(config['password'], '');
    });

    test('switching auth mode deletes the previous mode\'s secret', () async {
      final secure = MemoryBackend();
      final file = MemoryBackend();
      CredentialStore.debugUseBackends(secure: secure, file: file);

      await RommRepository.saveConfig(
        serverUrl: 'https://romm.example',
        apiKey: 'old-key',
      );
      await RommRepository.saveConfig(
        serverUrl: 'https://romm.example',
        username: 'neil',
        password: 'hunter2',
      );

      // Left behind, the stale key would be read back as a live API-key
      // connection for a server that now uses the password grant.
      expect(secure.values.containsKey('romm_api_key'), isFalse);
      expect(file.values.containsKey('romm_api_key'), isFalse);
      expect((await RommRepository.getConfig())!['api_key'], '');
    });

    test('getConfig migrates a legacy column and blanks it', () async {
      final secure = MemoryBackend();
      CredentialStore.debugUseBackends(secure: secure, file: MemoryBackend());
      await seedLegacyRow(password: 'hunter2');

      expect(await getConfigPassword(), 'hunter2');
      expect(secure.values['romm_password'], 'hunter2');
      expect((await readRow())['password'], '');

      // Re-reading is a no-op, and still returns the credential.
      expect(await getConfigPassword(), 'hunter2');
      expect((await readRow())['password'], '');
    });

    test('getConfig prefers the store over a stale column', () async {
      final secure = MemoryBackend()..values['romm_password'] = 'current';
      CredentialStore.debugUseBackends(secure: secure, file: MemoryBackend());
      await seedLegacyRow(password: 'stale');

      expect(await getConfigPassword(), 'current');
    });

    test('a session-only write leaves the legacy column alone', () async {
      // Nothing can persist: blanking here would disconnect a working server on
      // the next launch, which is worse than the leak being fixed.
      CredentialStore.debugUseBackends(secure: BrokenBackend(), file: null);
      await seedLegacyRow(password: 'hunter2');

      expect(await getConfigPassword(), 'hunter2');
      expect(
        (await readRow())['password'],
        base64Encode(utf8.encode('hunter2')),
      );
    });

    test('an unreadable store falls back without losing the row', () async {
      // No fallback store, so the read throws CredentialStoreException. That
      // means "could not look", not "no password".
      CredentialStore.debugUseBackends(secure: BrokenBackend(), file: null);
      await seedLegacyRow(password: 'hunter2');

      final config = await RommRepository.getConfig();

      expect(config, isNotNull);
      expect(config!['password'], 'hunter2');
      expect(config['server_url'], 'https://romm.example');
      expect(
        (await readRow())['password'],
        base64Encode(utf8.encode('hunter2')),
      );
    });

    test('clearConfig removes the secrets from the store too', () async {
      final secure = MemoryBackend();
      final file = MemoryBackend();
      CredentialStore.debugUseBackends(secure: secure, file: file);
      await RommRepository.saveConfig(
        serverUrl: 'https://romm.example',
        username: 'neil',
        password: 'hunter2',
      );

      await RommRepository.clearConfig();

      // A row deleted while the keychain kept the password would strand it
      // with nothing left pointing at it.
      expect(secure.values, isEmpty);
      expect(file.values, isEmpty);
      expect(await RommRepository.getConfig(), isNull);
    });
  });
}

/// The password from a full `getConfig()` read, for the many assertions that
/// only care about that one field.
Future<String?> getConfigPassword() async =>
    (await RommRepository.getConfig())?['password'] as String?;
