import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v135, which adds the ScreenScraper dump-identity cache
/// (`rom_crc32`, `rom_size`, `rom_fingerprint_skipped`) to `user_roms`.
///
/// The md5 deliberately reuses the pre-existing `ss_hash` column, so the
/// migration must not try to add it.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    // The "old device" schema: everything v131 had, and none of what v135 adds.
    db.execute('''
      CREATE TABLE user_roms (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        app_system_id TEXT,
        filename TEXT NOT NULL,
        rom_path TEXT NOT NULL COLLATE NOCASE,
        ra_hash TEXT,
        ss_hash TEXT,
        id_ra INTEGER,
        ra_match_source TEXT,
        ra_hash_skipped TEXT,
        is_favorite INTEGER DEFAULT 0
      )
    ''');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV135() => SqliteMigrations.migrateToVersion(db, 135);

  List<String> romColumns() => db
      .select('PRAGMA table_info(user_roms)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v135', () {
    test(
      'adds the fingerprint columns to a database that lacks them',
      () async {
        expect(romColumns(), isNot(contains('rom_crc32')));

        await runV135();

        expect(
          romColumns(),
          containsAll(['rom_crc32', 'rom_size', 'rom_fingerprint_skipped']),
        );
      },
    );

    test('leaves the existing ss_hash column alone', () async {
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, ss_hash) "
        "VALUES ('Game.zip', '/roms/nes/Game.zip', 'abc123')",
      );

      await runV135();

      final row = db.select(
        'SELECT ss_hash FROM user_roms WHERE rom_path = ?',
        ['/roms/nes/Game.zip'],
      );
      expect(row.first['ss_hash'], 'abc123');
    });

    test('is a no-op when re-run', () async {
      await runV135();
      final afterFirst = romColumns();

      // A device can see this migration twice; it must not throw on the second
      // pass, which a bare ALTER TABLE would.
      await runV135();

      expect(romColumns(), afterFirst);
    });

    test('creates the crc32 lookup index', () async {
      await runV135();

      final indexes = db
          .select("SELECT name FROM sqlite_master WHERE type = 'index'")
          .map((r) => r['name'].toString())
          .toList();
      expect(indexes, contains('idx_user_roms_rom_crc32'));
    });

    test('accepts a database that already has the columns', () async {
      db.execute('ALTER TABLE user_roms ADD COLUMN rom_crc32 TEXT');

      await runV135();

      expect(
        romColumns(),
        containsAll(['rom_crc32', 'rom_size', 'rom_fingerprint_skipped']),
      );
    });
  });
}
