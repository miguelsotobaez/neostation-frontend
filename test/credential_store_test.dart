import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/credential_backend.dart';
import 'package:neostation/services/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A backend that works, so the happy path can be asserted.
class _MemoryBackend implements CredentialBackend {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;

  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// A backend that fails the way a missing Secret Service does: every call
/// throws, including the read.
class _BrokenBackend implements CredentialBackend {
  @override
  Future<String?> read(String key) async {
    throw Exception('secret_service_get_sync: the name is not activatable');
  }

  @override
  Future<void> write(String key, String value) async {
    throw Exception('secret_password_storev_sync: Object does not exist');
  }

  @override
  Future<void> delete(String key) async {
    throw Exception('secret_service_get_sync: the name is not activatable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(CredentialStore.debugReset);

  test('prefers secure storage and keeps the fallback file clear', () async {
    final secure = _MemoryBackend();
    final file = _MemoryBackend()..values['token'] = 'stale';
    CredentialStore.debugUseBackends(secure: secure, file: file);

    final outcome = await CredentialStore.write('token', 'fresh');

    expect(outcome, CredentialWriteOutcome.secureStorage);
    expect(secure.values['token'], 'fresh');
    // A stale copy left behind would resurface the moment the keyring failed.
    expect(file.values, isEmpty);
    expect(await CredentialStore.read('token'), 'fresh');
  });

  test('falls back to the encrypted file when the keyring refuses', () async {
    final secure = _BrokenBackend();
    final file = _MemoryBackend();
    CredentialStore.debugUseBackends(secure: secure, file: file);

    final outcome = await CredentialStore.write('token', 'abc123');

    expect(outcome, CredentialWriteOutcome.encryptedFile);
    expect(file.values['token'], 'abc123');
    expect(await CredentialStore.read('token'), 'abc123');
  });

  test(
    'keeps the credential for the session when nothing can store it',
    () async {
      CredentialStore.debugUseBackends(secure: _BrokenBackend(), file: null);

      final outcome = await CredentialStore.write('token', 'abc123');

      // The session still works; only the next launch is signed out.
      expect(outcome, CredentialWriteOutcome.sessionOnly);
      expect(await CredentialStore.read('token'), 'abc123');
    },
  );

  test('reports an unreadable store instead of "not signed in"', () async {
    // No fallback store, as on mobile: a failed keystore read means "could not
    // look", and treating it as a signed-out user would delete a valid account.
    CredentialStore.debugUseBackends(secure: _BrokenBackend(), file: null);

    expect(
      () => CredentialStore.read('token'),
      throwsA(isA<CredentialStoreException>()),
    );
  });

  test('a healthy fallback answers for a broken keyring', () async {
    // The SteamOS case: libsecret always throws, so every launch would retry an
    // auto-login forever if an empty-but-working fallback did not settle it.
    CredentialStore.debugUseBackends(
      secure: _BrokenBackend(),
      file: _MemoryBackend(),
    );

    expect(await CredentialStore.read('token'), isNull);
  });

  test('returns null when the stores are readable and empty', () async {
    CredentialStore.debugUseBackends(
      secure: _MemoryBackend(),
      file: _MemoryBackend(),
    );

    expect(await CredentialStore.read('token'), isNull);
  });

  test(
    'migrates the legacy plaintext preference out of shared prefs',
    () async {
      SharedPreferences.setMockInitialValues({'auth_token': 'legacy-jwt'});
      final secure = _MemoryBackend();
      CredentialStore.debugUseBackends(secure: secure, file: _MemoryBackend());

      expect(await CredentialStore.read('auth_token'), 'legacy-jwt');
      expect(secure.values['auth_token'], 'legacy-jwt');

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.containsKey('auth_token'), isFalse);
    },
  );

  test('delete clears every store, including a failing one', () async {
    final file = _MemoryBackend()..values['token'] = 'abc123';
    CredentialStore.debugUseBackends(secure: _BrokenBackend(), file: file);
    await CredentialStore.write('token', 'abc123');

    await CredentialStore.delete('token');

    // The keyring throwing must not stop the other stores being cleared.
    expect(file.values, isEmpty);
  });
}
