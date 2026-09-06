import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Pins the reason this branch's migrations are numbered 139/140 rather than
/// 136/137.
///
/// Main reached v138 (`ra_seed_stamp`, #399) while this branch held 136 and
/// 137. The numbers never collided — main picked 138 precisely to avoid them —
/// but a device that upgraded on main is already **past** 136 and 137, so those
/// cases would never have run on it: no `user_collections` tables, no
/// `collection_sort_*` columns, and every whole-config save failing with
/// `no such column`.
///
/// Being below the current version is a different failure from colliding with
/// it, and it is the silent one. These cases model that device: a schema that
/// has been through main's v138 and has none of this branch's work.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    // What a device upgraded on main looks like: user_config carries the RA
    // stamp v138 added, and nothing from this branch exists.
    db.execute('''
      CREATE TABLE user_config (
        id INTEGER PRIMARY KEY,
        system_sort_by TEXT DEFAULT 'alphabetical',
        system_sort_order TEXT DEFAULT 'asc',
        ra_seed_stamp TEXT DEFAULT ''
      )
    ''');
    db.execute('INSERT INTO user_config (id) VALUES (1)');
    db.execute('''
      CREATE TABLE user_roms (
        filename TEXT,
        rom_path TEXT NOT NULL UNIQUE COLLATE NOCASE,
        app_system_id TEXT,
        is_favorite INTEGER DEFAULT 0,
        is_hidden INTEGER DEFAULT 0
      )
    ''');
  });

  tearDown(() {
    db.close();
  });

  List<String> tableNames() => db
      .select("SELECT name FROM sqlite_master WHERE type = 'table'")
      .map((r) => r['name'].toString())
      .toList();

  List<String> configColumns() => db
      .select('PRAGMA table_info(user_config)')
      .map((c) => c['name'].toString())
      .toList();

  group('a device that upgraded on main (v138)', () {
    test('gains the collections tables from v139', () async {
      expect(tableNames(), isNot(contains('user_collections')));

      await SqliteMigrations.migrateToVersion(db, 139);

      expect(tableNames(), contains('user_collections'));
      expect(tableNames(), contains('user_collection_items'));
    });

    test('gains the sort columns from v140', () async {
      expect(configColumns(), isNot(contains('collection_sort_by')));

      await SqliteMigrations.migrateToVersion(db, 140);

      expect(configColumns(), contains('collection_sort_by'));
      expect(configColumns(), contains('collection_sort_order'));
    });

    test('running both leaves the RA stamp v138 added untouched', () async {
      db.execute("UPDATE user_config SET ra_seed_stamp = 'seed-abc'");

      await SqliteMigrations.migrateToVersion(db, 139);
      await SqliteMigrations.migrateToVersion(db, 140);

      final row = db.select('SELECT * FROM user_config WHERE id = 1').first;
      expect(row['ra_seed_stamp'], 'seed-abc');
    });
  });

  group('a device that already ran the old 136/137', () {
    test('re-runs both as a no-op rather than failing', () async {
      // First pass stands in for the old numbering having already run.
      await SqliteMigrations.migrateToVersion(db, 139);
      await SqliteMigrations.migrateToVersion(db, 140);
      db.execute('''
        INSERT INTO user_collections (id, name, sort_order)
        VALUES ('keep-me', 'Kept', 0)
      ''');
      db.execute("UPDATE user_config SET collection_sort_by = 'game_count'");

      // Second pass is the renumbered slot arriving on that same device.
      await SqliteMigrations.migrateToVersion(db, 139);
      await SqliteMigrations.migrateToVersion(db, 140);

      final rows = db.select('SELECT id FROM user_collections');
      expect(rows.length, 1, reason: 'existing collections must survive');
      expect(rows.first['id'], 'keep-me');
      final config = db.select('SELECT * FROM user_config WHERE id = 1').first;
      expect(
        config['collection_sort_by'],
        'game_count',
        reason: "the user's sort choice must not be reset",
      );
    });
  });

  group('a device that upgraded on main past v140 (0.11.0, v144)', () {
    // The case reserving 139/140 does not cover: main kept moving and shipped
    // 141 and 144, then 146/147, then 149, then 150-153, so a 0.11.0 device is
    // past both slots. The upgrade loop only walks oldVersion + 1 ..=
    // newVersion, so 139 and 140 never fire there and only a migration above
    // the floor can reach it -- which is why this repair has been renumbered
    // on every rebase: 145, 148, 150, 154, now 155.
    test(
      'v155 creates the collections tables the skipped v139 would have',
      () async {
        expect(tableNames(), isNot(contains('user_collections')));

        await SqliteMigrations.migrateToVersion(db, 155);

        expect(tableNames(), contains('user_collections'));
        expect(tableNames(), contains('user_collection_items'));
      },
    );

    test('v155 adds the sort columns the skipped v140 would have', () async {
      expect(configColumns(), isNot(contains('collection_sort_by')));

      await SqliteMigrations.migrateToVersion(db, 155);

      expect(configColumns(), contains('collection_sort_by'));
      expect(configColumns(), contains('collection_sort_order'));
    });

    test('v155 leaves what main added untouched', () async {
      db.execute("UPDATE user_config SET ra_seed_stamp = 'seed-abc'");

      await SqliteMigrations.migrateToVersion(db, 155);

      final row = db.select('SELECT * FROM user_config WHERE id = 1').first;
      expect(row['ra_seed_stamp'], 'seed-abc');
    });

    test('v155 is a no-op on a device that did run 139/140', () async {
      await SqliteMigrations.migrateToVersion(db, 139);
      await SqliteMigrations.migrateToVersion(db, 140);
      db.execute('''
        INSERT INTO user_collections (id, name, sort_order)
        VALUES ('keep-me', 'Kept', 0)
      ''');
      db.execute("UPDATE user_config SET collection_sort_by = 'game_count'");

      await SqliteMigrations.migrateToVersion(db, 155);

      final rows = db.select('SELECT id FROM user_collections');
      expect(rows.length, 1, reason: 'existing collections must survive');
      expect(rows.first['id'], 'keep-me');
      final config = db.select('SELECT * FROM user_config WHERE id = 1').first;
      expect(
        config['collection_sort_by'],
        'game_count',
        reason: "the user's sort choice must not be reset",
      );
    });

    test('running v155 twice is a no-op', () async {
      await SqliteMigrations.migrateToVersion(db, 155);
      db.execute('''
        INSERT INTO user_collections (id, name, sort_order)
        VALUES ('keep-me', 'Kept', 0)
      ''');

      await SqliteMigrations.migrateToVersion(db, 155);

      final rows = db.select('SELECT id FROM user_collections');
      expect(rows.length, 1);
      expect(configColumns(), contains('collection_sort_by'));
    });
  });
}
