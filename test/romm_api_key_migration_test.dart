import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';
import 'package:sqlite3/sqlite3.dart';

/// Tests for migration v131, which adds `user_romm_config.api_key` so a RomM
/// server can be connected with a Client API Token instead of a password.
///
/// The "old device" case is a database created before v131: it has the v111
/// table without the column.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
  });

  tearDown(() {
    db.close();
  });

  void createLegacyTable() {
    db.execute('''
      CREATE TABLE user_romm_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        server_url TEXT,
        username TEXT,
        password TEXT,
        access_token TEXT,
        refresh_token TEXT,
        token_expires INTEGER,
        last_verified TEXT,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
  }

  Future<void> runV131() => SqliteMigrations.migrateToVersion(db, 131);

  List<String> configColumns() => db
      .select('PRAGMA table_info(user_romm_config)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v131', () {
    test('adds api_key when the column is missing', () async {
      createLegacyTable();

      await runV131();

      expect(configColumns(), contains('api_key'));
    });

    test('is a no-op when api_key already exists', () async {
      createLegacyTable();
      db.execute('ALTER TABLE user_romm_config ADD COLUMN api_key TEXT');

      await runV131();

      expect(configColumns(), contains('api_key'));
      expect(
        configColumns().where((c) => c == 'api_key'),
        hasLength(1),
        reason: 'Re-running must not duplicate the column',
      );
    });

    test('preserves an existing password-grant connection', () async {
      createLegacyTable();
      db.execute(
        "INSERT INTO user_romm_config (id, server_url, username, password) "
        "VALUES (1, 'https://romm.local', 'testuser', 'czNjcmV0')",
      );

      await runV131();

      final row = db.select('SELECT * FROM user_romm_config').first;
      expect(row['server_url'], 'https://romm.local');
      expect(row['username'], 'testuser');
      expect(row['password'], 'czNjcmV0');
      // Nothing backfills the new column: an empty key is what keeps this
      // connection on the password grant.
      expect(row['api_key'], isNull);
    });

    test('tolerates a database that never had the RomM table', () async {
      await runV131();

      expect(configColumns(), isEmpty);
    });

    test('the fresh-install CREATE already carries api_key', () {
      db.execute(SqliteMigrations.createUserRommConfigTableSql);

      expect(configColumns(), contains('api_key'));
    });
  });
}
