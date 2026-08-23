import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v144, which reopens disc ROMs parked while the CHD
/// reader misread cooked tracks.
///
/// A CHD written by `chdman createcd` from a `.iso` holds one `MODE1` track
/// whose frames are user data from byte zero, and the reader stepped over a
/// sector header that is not there. The hash came back null and the ROM was
/// parked as `ra_hash_skipped = 'error'`, which the match pass then walks past
/// for good — so without this the fix would reach only newly added ROMs.
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
      "VALUES ('ps2', 'ps2', 'PlayStation 2', 21, 1)",
    );
    db.execute(
      "INSERT INTO app_systems (id, folder_name, real_name, ra_id) "
      "VALUES ('nes', 'nes', 'NES', 7)",
    );
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV144() => SqliteMigrations.migrateToVersion(db, 144);

  void addRom(String filename, String system, String? skipped) {
    db.execute(
      'INSERT INTO user_roms (filename, rom_path, app_system_id, '
      'ra_hash_skipped) VALUES (?, ?, ?, ?)',
      [filename, '/roms/$system/$filename', system, skipped],
    );
  }

  Object? skipReason(String filename) => db.select(
    'SELECT ra_hash_skipped FROM user_roms WHERE filename = ?',
    [filename],
  ).single['ra_hash_skipped'];

  group('migration v144', () {
    test('unparks a disc ROM the reader failed on', () async {
      addRom('game.chd', 'ps2', 'error');

      await runV144();

      expect(skipReason('game.chd'), isNull);
    });

    test('unparks a disc ROM parked as an unreadable container', () async {
      addRom('other.chd', 'ps2', 'disc');

      await runV144();

      expect(skipReason('other.chd'), isNull);
    });

    test('leaves reasons this fix does not address parked', () async {
      // A file that is gone or over the size cap still cannot be hashed.
      addRom('gone.chd', 'ps2', 'missing');
      addRom('huge.chd', 'ps2', 'oversize');

      await runV144();

      expect(skipReason('gone.chd'), 'missing');
      expect(skipReason('huge.chd'), 'oversize');
    });

    test('leaves a cartridge ROM parked as an error alone', () async {
      // `error` is the bulk pass's general bucket, so a cartridge under it
      // failed for some other reason and re-walking it would just fail again.
      addRom('bad.nes', 'nes', 'error');

      await runV144();

      expect(skipReason('bad.nes'), 'error');
    });

    test('leaves a matched disc ROM untouched', () async {
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash, "
        "id_ra) VALUES ('done.chd', '/roms/ps2/done.chd', 'ps2', 'realhash', "
        "99)",
      );

      await runV144();

      final row = db.select(
        'SELECT ra_hash, id_ra, ra_hash_skipped FROM user_roms '
        'WHERE filename = ?',
        ['done.chd'],
      ).single;
      expect(row['ra_hash'], 'realhash');
      expect(row['id_ra'], 99);
      expect(row['ra_hash_skipped'], isNull);
    });

    test('re-running changes nothing further', () async {
      addRom('game.chd', 'ps2', 'error');
      addRom('bad.nes', 'nes', 'error');

      await runV144();
      final after = db.select('SELECT * FROM user_roms ORDER BY rom_path');

      await runV144();

      expect(
        db.select('SELECT * FROM user_roms ORDER BY rom_path').toString(),
        after.toString(),
      );
    });

    test('survives a database with no ra_hash_skipped column', () async {
      // The version is a floor, not a guarantee every migration ran, so the
      // column this one depends on may genuinely not be there.
      final old = sqlite3.openInMemory();
      old.execute(
        'CREATE TABLE user_roms (filename TEXT, rom_path TEXT PRIMARY KEY)',
      );
      old.execute(
        'CREATE TABLE app_systems (id TEXT PRIMARY KEY, folder_name TEXT)',
      );

      await expectLater(SqliteMigrations.migrateToVersion(old, 144), completes);

      old.close();
    });
  });
}
