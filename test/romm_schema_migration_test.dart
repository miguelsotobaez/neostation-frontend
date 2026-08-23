import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v119, which creates the entire RomM schema in one step:
///
/// Renumbered three times while this branch was open: v111 -> v114 when main
/// claimed v111-v113 (#318), v114 -> v115 when main claimed v114 (#319), then
/// v115 -> v119 when main claimed v115-v118 for NeoSync v2 (#336).
/// See [SqliteMigrations].
/// the config/rom-map/playtime tables, the `hide_tab_romm` flag, and the
/// provider-scoping rebuild of `app_neo_sync_state`.
///
/// Each half has to stay a no-op on a database that already has it — a fresh
/// install gets these tables from the create-table list and then runs the
/// migration anyway.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    // v119 adds a column to user_config, which every real database has by then.
    db.execute('CREATE TABLE user_config (id INTEGER PRIMARY KEY)');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV119() => SqliteMigrations.migrateToVersion(db, 119);

  bool tableExists(String name) => db.select(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1",
    [name],
  ).isNotEmpty;

  Set<String> columnsOf(String table) => db
      .select('PRAGMA table_info($table)')
      .map((r) => r['name'].toString())
      .toSet();

  test('creates every RomM table and the nav-tab flag', () async {
    expect(tableExists('user_romm_config'), isFalse);

    await runV119();

    expect(tableExists('user_romm_config'), isTrue);
    expect(tableExists('app_romm_rom_map'), isTrue);
    expect(tableExists('app_romm_play_sessions'), isTrue);
    expect(tableExists('app_romm_playtime_state'), isTrue);
    expect(tableExists('app_neo_sync_state'), isTrue);
    expect(columnsOf('user_config'), contains('hide_tab_romm'));
  });

  // A device that ran the pre-merge RomM build sits at user_version 110
  // without main's game_details_tab column, so it upgrades straight to v119
  // and never runs v110. Every config write names that column, so v119 has to
  // add it too or the first save throws "no such column".
  test('adds game_details_tab for a database that skipped v110', () async {
    expect(columnsOf('user_config'), isNot(contains('game_details_tab')));

    await runV119();

    expect(columnsOf('user_config'), contains('game_details_tab'));
  });

  test('leaves an existing game_details_tab value alone', () async {
    db.execute(
      "ALTER TABLE user_config ADD COLUMN game_details_tab TEXT DEFAULT 'wheel'",
    );
    db.execute(
      "INSERT INTO user_config (id, game_details_tab) VALUES (1, 'gameInfo')",
    );

    await runV119();

    final row = db.select('SELECT game_details_tab FROM user_config').single;
    expect(row['game_details_tab'], 'gameInfo');
  });

  test(
    'is a no-op when the tables already exist, keeping their rows',
    () async {
      db.execute(SqliteMigrations.createUserRommConfigTableSql);
      db.execute(SqliteMigrations.createAppRommRomMapTableSql);
      db.execute(SqliteMigrations.createAppRommRomMapIndexSql);
      db.execute(SqliteMigrations.createAppRommPlaySessionsTableSql);
      db.execute(SqliteMigrations.createAppRommPlaySessionsIndexSql);
      db.execute(SqliteMigrations.createAppRommPlaytimeStateTableSql);
      db.execute(
        "INSERT INTO user_romm_config (id, server_url, username) "
        "VALUES (1, 'https://romm.local', 'testuser')",
      );

      await runV119();

      final rows = db.select(
        'SELECT server_url, username FROM user_romm_config',
      );
      expect(rows, hasLength(1));
      expect(rows.first['server_url'], 'https://romm.local');
      expect(rows.first['username'], 'testuser');
    },
  );

  test('provider-scopes a legacy app_neo_sync_state', () async {
    // The pre-v119 shape: keyed on file_path alone, no provider column.
    db.execute('''
      CREATE TABLE app_neo_sync_state (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_path TEXT NOT NULL UNIQUE,
        local_modified_at INTEGER NOT NULL,
        cloud_updated_at INTEGER NOT NULL,
        file_size INTEGER NOT NULL,
        file_hash TEXT
      )
    ''');
    db.execute(
      "INSERT INTO app_neo_sync_state "
      "(file_path, local_modified_at, cloud_updated_at, file_size, file_hash) "
      "VALUES ('/saves/game.srm', 1, 2, 3, 'abc')",
    );

    await runV119();

    expect(columnsOf('app_neo_sync_state'), contains('provider'));
    final rows = db.select(
      'SELECT provider, file_path, file_hash FROM app_neo_sync_state',
    );
    expect(rows, hasLength(1));
    // Historic rows were all written by NeoSync, so they must be attributed to
    // it rather than silently inherited by RomM.
    expect(rows.first['provider'], 'neosync');
    expect(rows.first['file_path'], '/saves/game.srm');
    expect(rows.first['file_hash'], 'abc');
  });

  test('lets both providers hold state for the same file afterwards', () async {
    await runV119();

    db.execute(
      "INSERT INTO app_neo_sync_state "
      "(provider, file_path, local_modified_at, cloud_updated_at, file_size) "
      "VALUES ('neosync', '/saves/game.srm', 1, 2, 3)",
    );
    db.execute(
      "INSERT INTO app_neo_sync_state "
      "(provider, file_path, local_modified_at, cloud_updated_at, file_size) "
      "VALUES ('romm', '/saves/game.srm', 4, 5, 6)",
    );

    final rows = db.select(
      'SELECT provider FROM app_neo_sync_state ORDER BY provider',
    );
    expect(rows.map((r) => r['provider']), ['neosync', 'romm']);
  });
}
