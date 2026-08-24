import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/repositories/scraper_repository.dart';
import 'package:neostation/services/credential_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_test_helper.dart';
import 'fake_credential_backends.dart';

/// Writes a row the way a pre-migration build does: the password base64-encoded
/// straight into the column, alongside the non-secret tier data.
Future<void> seedLegacyRow({String password = 'hunter2'}) async {
  final db = await SqliteService.getDatabase();
  await db.insert('user_screenscraper_credentials', {
    'id': 1,
    'username': 'neil',
    'password': base64Encode(utf8.encode(password)),
    'user_id': '12345',
    'level': '3',
    'max_requests_per_day': 20000,
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<Object?> readPasswordColumn() async {
  final db = await SqliteService.getDatabase();
  final rows = await db.query('user_screenscraper_credentials');
  return rows.isEmpty ? null : rows.first['password'];
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

  group('ScraperRepository secrets', () {
    test('saveCredentials keeps the password out of the database', () async {
      final secure = MemoryBackend();
      CredentialStore.debugUseBackends(secure: secure, file: MemoryBackend());

      await ScraperRepository.saveCredentials('neil', 'hunter2', {
        'numid': '12345',
        'niveau': '3',
      });

      expect(secure.values['screenscraper_password'], 'hunter2');
      expect(await readPasswordColumn(), '');

      final saved = await ScraperRepository.getSavedCredentials();
      expect(saved!['password'], 'hunter2');
      expect(saved['username'], 'neil');
      // The non-secret tier data must stay in SQLite.
      expect(saved['id'], '12345');
      expect(saved['level'], '3');
    });

    test(
      'getSavedCredentials migrates a legacy column and blanks it',
      () async {
        final secure = MemoryBackend();
        CredentialStore.debugUseBackends(secure: secure, file: MemoryBackend());
        await seedLegacyRow();

        final saved = await ScraperRepository.getSavedCredentials();

        expect(saved!['password'], 'hunter2');
        expect(secure.values['screenscraper_password'], 'hunter2');
        expect(await readPasswordColumn(), '');
        // The tier data survives the move.
        expect(saved['max_requests_per_day'], '20000');

        // Re-reading is a no-op and still returns the password.
        final again = await ScraperRepository.getSavedCredentials();
        expect(again!['password'], 'hunter2');
        expect(await readPasswordColumn(), '');
      },
    );

    test('getSavedCredentials prefers the store over a stale column', () async {
      final secure = MemoryBackend()
        ..values['screenscraper_password'] = 'current';
      CredentialStore.debugUseBackends(secure: secure, file: MemoryBackend());
      await seedLegacyRow(password: 'stale');

      final saved = await ScraperRepository.getSavedCredentials();

      expect(saved!['password'], 'current');
    });

    test('a session-only write leaves the legacy column alone', () async {
      CredentialStore.debugUseBackends(secure: BrokenBackend(), file: null);
      await seedLegacyRow();

      final saved = await ScraperRepository.getSavedCredentials();

      expect(saved!['password'], 'hunter2');
      expect(await readPasswordColumn(), base64Encode(utf8.encode('hunter2')));
    });

    test('an unreadable store still returns the credentials', () async {
      CredentialStore.debugUseBackends(secure: BrokenBackend(), file: null);
      await seedLegacyRow();

      final saved = await ScraperRepository.getSavedCredentials();

      expect(saved, isNotNull);
      expect(saved!['password'], 'hunter2');
      expect(await readPasswordColumn(), base64Encode(utf8.encode('hunter2')));
    });

    test('a null password column reads as no password, not an error', () async {
      // The old read decoded unguarded, so a null column threw and the whole
      // account was reported as "no credentials saved".
      CredentialStore.debugUseBackends(
        secure: MemoryBackend(),
        file: MemoryBackend(),
      );
      final db = await SqliteService.getDatabase();
      await db.insert('user_screenscraper_credentials', {
        'id': 1,
        'username': 'neil',
        'password': null,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      final saved = await ScraperRepository.getSavedCredentials();

      expect(saved, isNotNull);
      expect(saved!['username'], 'neil');
      expect(saved['password'], '');
    });

    test('clearCredentials removes the password from the store too', () async {
      final secure = MemoryBackend();
      final file = MemoryBackend();
      CredentialStore.debugUseBackends(secure: secure, file: file);
      await ScraperRepository.saveCredentials('neil', 'hunter2');

      await ScraperRepository.clearCredentials();

      expect(secure.values, isEmpty);
      expect(file.values, isEmpty);
      expect(await ScraperRepository.getSavedCredentials(), isNull);
    });
  });

  group('ScraperRepository startup sweep', () {
    test('moves a dormant legacy password out of the database', () async {
      // The case the read path cannot reach: nothing reads ScreenScraper
      // credentials on launch, so without this sweep the password would sit in
      // data.sqlite until the user next scraped.
      final secure = MemoryBackend();
      CredentialStore.debugUseBackends(secure: secure, file: MemoryBackend());
      await seedLegacyRow();

      await ScraperRepository.migrateLegacyPasswordToCredentialStore();

      expect(secure.values['screenscraper_password'], 'hunter2');
      expect(await readPasswordColumn(), '');
    });

    test('is a no-op once the column is empty', () async {
      final secure = MemoryBackend()
        ..values['screenscraper_password'] = 'hunter2';
      CredentialStore.debugUseBackends(secure: secure, file: MemoryBackend());
      await seedLegacyRow();
      await ScraperRepository.migrateLegacyPasswordToCredentialStore();

      await ScraperRepository.migrateLegacyPasswordToCredentialStore();

      expect(secure.values['screenscraper_password'], 'hunter2');
      expect(await readPasswordColumn(), '');
    });

    test('leaves the column alone when nothing can persist', () async {
      CredentialStore.debugUseBackends(secure: BrokenBackend(), file: null);
      await seedLegacyRow();

      await ScraperRepository.migrateLegacyPasswordToCredentialStore();

      expect(await readPasswordColumn(), base64Encode(utf8.encode('hunter2')));
    });

    test('does not throw when there are no credentials at all', () async {
      CredentialStore.debugUseBackends(
        secure: MemoryBackend(),
        file: MemoryBackend(),
      );

      // Runs on every launch, including for the majority who never set the
      // scraper up. It must not throw into startup.
      await ScraperRepository.migrateLegacyPasswordToCredentialStore();
    });
  });
}
