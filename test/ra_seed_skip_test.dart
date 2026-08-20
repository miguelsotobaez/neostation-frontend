import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:neostation/data/datasources/sqlite_service.dart';

/// B1: `refreshRetroAchievementsData()` used to DELETE and re-insert all 18,079
/// rows of the bundled RetroAchievements seed on every single launch. It now
/// skips that when the asset's generation stamp matches the one recorded by the
/// last successful seed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late sqlite.Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = sqlite.sqlite3.openInMemory();
    final adapter = DatabaseAdapter(db);
    SqliteService.setTestingDatabase(adapter);
    await adapter.execute('''
      CREATE TABLE user_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        systems_version TEXT DEFAULT '',
        ra_seed_stamp TEXT DEFAULT ''
      )
    ''');
    await adapter.execute('INSERT INTO user_config (id) VALUES (1)');
    await adapter.execute('''
      CREATE TABLE app_ra_game_list (
        id INTEGER, game_id INTEGER NOT NULL, title TEXT NOT NULL,
        console_id INTEGER NOT NULL, console_name TEXT NOT NULL,
        image_icon TEXT, num_achievements INTEGER NOT NULL DEFAULT 0,
        num_leaderboards INTEGER NOT NULL DEFAULT 0,
        points INTEGER NOT NULL DEFAULT 0, date_modified TEXT,
        forum_topic_id INTEGER, hash TEXT NOT NULL
      )
    ''');
  });

  tearDown(() {
    db.close();
  });

  int rowCount() =>
      db.select('SELECT COUNT(*) AS c FROM app_ra_game_list').first['c'] as int;

  String storedStamp() =>
      db
              .select('SELECT ra_seed_stamp FROM user_config WHERE id = 1')
              .first['ra_seed_stamp']
          as String;

  test(
    'the first seed populates the table and records the asset stamp',
    () async {
      expect(storedStamp(), '');

      await SqliteService.instance.refreshRetroAchievementsData();

      expect(rowCount(), greaterThan(0));
      expect(storedStamp(), startsWith('-- Auto-generated on '));
    },
  );

  test('a second call with an unchanged asset skips the re-seed', () async {
    await SqliteService.instance.refreshRetroAchievementsData();
    final seeded = rowCount();

    // A sentinel row survives only if the DELETE never runs.
    db.execute(
      "INSERT INTO app_ra_game_list (id, game_id, title, console_id, "
      "console_name, hash) VALUES (-1, -1, 'sentinel', 0, 'x', 'y')",
    );

    await SqliteService.instance.refreshRetroAchievementsData();

    expect(rowCount(), seeded + 1, reason: 'the table was rebuilt anyway');
    final sentinel = db.select(
      "SELECT * FROM app_ra_game_list WHERE title = 'sentinel'",
    );
    expect(sentinel, hasLength(1));
  });

  test('a changed stamp re-seeds', () async {
    await SqliteService.instance.refreshRetroAchievementsData();
    final seeded = rowCount();

    db.execute("UPDATE user_config SET ra_seed_stamp = 'stale' WHERE id = 1");
    db.execute(
      "INSERT INTO app_ra_game_list (id, game_id, title, console_id, "
      "console_name, hash) VALUES (-1, -1, 'sentinel', 0, 'x', 'y')",
    );

    await SqliteService.instance.refreshRetroAchievementsData();

    expect(rowCount(), seeded, reason: 'a changed asset must rebuild');
    expect(storedStamp(), startsWith('-- Auto-generated on '));
  });

  test('a matching stamp over an empty table still re-seeds', () async {
    await SqliteService.instance.refreshRetroAchievementsData();
    final seeded = rowCount();

    // The stamp says "done", but the rows are gone — a recreated table, or a
    // seed that half-applied. Trusting the stamp here would leave the app with
    // an RA list it never rebuilds.
    db.execute('DELETE FROM app_ra_game_list');

    await SqliteService.instance.refreshRetroAchievementsData();

    expect(rowCount(), seeded);
  });
}
