import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v130, which adds `app_systems.ra_hash_algo` and
/// `app_systems.ra_hash_mode` — the per-system RetroAchievements hashing policy
/// that used to be three hardcoded lists in the hash service.
void main() {
  late Database db;

  setUp(() {
    // The "old device" case: app_systems without the policy columns.
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE app_systems (
        id TEXT PRIMARY KEY,
        folder_name TEXT NOT NULL UNIQUE,
        real_name TEXT NOT NULL,
        ra_id INTEGER,
        multidisc INTEGER NOT NULL DEFAULT 0
      )
    ''');
    db.execute('''
      CREATE TABLE user_roms (
        filename TEXT,
        rom_path TEXT PRIMARY KEY,
        app_system_id TEXT,
        ra_hash TEXT,
        id_ra INTEGER,
        ra_match_source TEXT,
        ra_hash_skipped TEXT
      )
    ''');
    db.execute(
      "INSERT INTO app_systems (id, folder_name, real_name, ra_id) "
      "VALUES ('nes', 'nes', 'NES', 7)",
    );
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV130() => SqliteMigrations.migrateToVersion(db, 130);

  List<String> systemColumns() => db
      .select('PRAGMA table_info(app_systems)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v130', () {
    test('adds both policy columns when they are missing', () async {
      expect(systemColumns(), isNot(contains('ra_hash_algo')));
      expect(systemColumns(), isNot(contains('ra_hash_mode')));

      await runV130();

      expect(systemColumns(), contains('ra_hash_algo'));
      expect(systemColumns(), contains('ra_hash_mode'));
    });

    test('is a no-op when both columns already exist', () async {
      await runV130();
      final after = systemColumns();

      await runV130();

      expect(systemColumns(), after);
    });

    test('adds only the column that is missing', () async {
      db.execute('ALTER TABLE app_systems ADD COLUMN ra_hash_algo TEXT');

      await runV130();

      final columns = systemColumns();
      expect(columns.where((c) => c == 'ra_hash_algo'), hasLength(1));
      expect(columns, contains('ra_hash_mode'));
    });

    test('clears the stale hash on a corrected hack folder', () async {
      db.execute(
        "INSERT INTO app_systems (id, folder_name, real_name, ra_id) "
        "VALUES ('nes-hacks', 'nes-hacks', 'NES Hacks', 7)",
      );
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash, "
        "id_ra) VALUES ('h.nes', '/roms/nes-hacks/h.nes', 'nes-hacks', "
        "'wrongalgo', 999)",
      );

      await runV130();

      final row = db
          .select(
            "SELECT ra_hash, id_ra FROM user_roms WHERE filename = 'h.nes'",
          )
          .single;
      expect(row['ra_hash'], isNull);
      expect(row['id_ra'], isNull);
    });

    test('leaves a hand-picked match on a hack folder alone', () async {
      db.execute(
        "INSERT INTO app_systems (id, folder_name, real_name, ra_id) "
        "VALUES ('nes-hacks', 'nes-hacks', 'NES Hacks', 7)",
      );
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash, "
        "id_ra, ra_match_source) VALUES ('m.nes', '/roms/nes-hacks/m.nes', "
        "'nes-hacks', 'picked', 555, 'manual')",
      );

      await runV130();

      final row = db
          .select(
            "SELECT ra_hash, id_ra FROM user_roms WHERE filename = 'm.nes'",
          )
          .single;
      expect(row['ra_hash'], 'picked');
      expect(row['id_ra'], 555);
    });

    test('leaves ROMs on other systems untouched', () async {
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash, "
        "id_ra) VALUES ('a.nes', '/roms/nes/a.nes', 'nes', 'goodhash', 42)",
      );

      await runV130();

      final row = db
          .select(
            "SELECT ra_hash, id_ra FROM user_roms WHERE filename = 'a.nes'",
          )
          .single;
      expect(row['ra_hash'], 'goodhash');
      expect(row['id_ra'], 42);
    });

    test('leaves existing rows alone — syncSystems refills them', () async {
      await runV130();

      final row = db
          .select("SELECT * FROM app_systems WHERE folder_name = 'nes'")
          .single;
      expect(row['ra_id'], 7);
      // Null reads as the permissive default, which is what an undeclared
      // system did before the policy became data.
      expect(row['ra_hash_algo'], isNull);
      expect(row['ra_hash_mode'], isNull);
    });
  });
}
