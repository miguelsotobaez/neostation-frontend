import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v134, which reopens disc ROMs now that they can be
/// hashed properly.
///
/// Everything a disc system had stored before was unusable: ROMs the bulk pass
/// reached were parked as `ra_hash_skipped = 'disc'`, and the few the lazy path
/// reached carry a whole-file MD5 of the container, which RetroAchievements has
/// never registered for anything. Neither state is ever revisited on its own —
/// the pass walks ROMs with no hash and skips parked ones — so without this the
/// disc support would reach only newly added ROMs.
void main() {
  late Database db;

  setUp(() {
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
      "INSERT INTO app_systems (id, folder_name, real_name, ra_id, multidisc) "
      "VALUES ('ps1', 'ps1', 'PlayStation', 12, 1)",
    );
    db.execute(
      "INSERT INTO app_systems (id, folder_name, real_name, ra_id) "
      "VALUES ('nes', 'nes', 'NES', 7)",
    );
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV134() => SqliteMigrations.migrateToVersion(db, 134);

  Map<String, Object?> rom(String filename) => db.select(
    'SELECT ra_hash, id_ra, ra_hash_skipped FROM user_roms '
    'WHERE filename = ?',
    [filename],
  ).single;

  group('migration v134', () {
    test('unparks a ROM skipped as an unhashable disc', () async {
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, "
        "ra_hash_skipped) VALUES ('game.chd', '/roms/ps1/game.chd', 'ps1', "
        "'disc')",
      );

      await runV134();

      expect(rom('game.chd')['ra_hash_skipped'], isNull);
    });

    test('leaves other skip reasons parked', () async {
      // A missing file or a failed extraction is still a real problem; only
      // the disc marker became obsolete.
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, "
        "ra_hash_skipped) VALUES ('gone.nes', '/roms/nes/gone.nes', 'nes', "
        "'missing')",
      );

      await runV134();

      expect(rom('gone.nes')['ra_hash_skipped'], 'missing');
    });

    test('clears the container hash a disc ROM was given', () async {
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash, "
        "id_ra) VALUES ('old.chd', '/roms/ps1/old.chd', 'ps1', "
        "'wholefilemd5', 777)",
      );

      await runV134();

      expect(rom('old.chd')['ra_hash'], isNull);
      expect(rom('old.chd')['id_ra'], isNull);
    });

    test('leaves a hand-picked match on a disc system alone', () async {
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash, "
        "id_ra, ra_match_source) VALUES ('picked.chd', '/roms/ps1/picked.chd', "
        "'ps1', 'wholefilemd5', 555, 'manual')",
      );

      await runV134();

      expect(rom('picked.chd')['ra_hash'], 'wholefilemd5');
      expect(rom('picked.chd')['id_ra'], 555);
    });

    test('leaves cartridge ROMs untouched', () async {
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash, "
        "id_ra) VALUES ('a.nes', '/roms/nes/a.nes', 'nes', 'goodhash', 42)",
      );

      await runV134();

      expect(rom('a.nes')['ra_hash'], 'goodhash');
      expect(rom('a.nes')['id_ra'], 42);
    });

    test('re-running changes nothing further', () async {
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash, "
        "id_ra) VALUES ('a.nes', '/roms/nes/a.nes', 'nes', 'goodhash', 42)",
      );
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, "
        "ra_hash_skipped) VALUES ('game.chd', '/roms/ps1/game.chd', 'ps1', "
        "'disc')",
      );

      await runV134();
      final after = db.select('SELECT * FROM user_roms ORDER BY rom_path');

      await runV134();

      expect(
        db.select('SELECT * FROM user_roms ORDER BY rom_path').toString(),
        after.toString(),
      );
    });

    test('survives a database whose user_roms predates ra_hash', () async {
      // The version is a floor, not a guarantee every migration ran, so a
      // column this one depends on may genuinely not be there.
      final old = sqlite3.openInMemory();
      old.execute(
        'CREATE TABLE user_roms (filename TEXT, rom_path TEXT PRIMARY KEY)',
      );
      old.execute(
        'CREATE TABLE app_systems (id TEXT PRIMARY KEY, folder_name TEXT)',
      );

      await expectLater(SqliteMigrations.migrateToVersion(old, 134), completes);

      old.close();
    });
  });
}
