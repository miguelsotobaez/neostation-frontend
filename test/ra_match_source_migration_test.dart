import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v126, which adds `user_roms.ra_match_source` — the
/// column that records how a RetroAchievements match was established and keeps
/// the bulk re-match pass from overwriting a game the user picked by hand.
void main() {
  late Database db;

  setUp(() {
    // The "old device" case: user_roms without the new column.
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE user_roms (
        filename TEXT,
        rom_path TEXT PRIMARY KEY,
        app_system_id TEXT,
        ra_hash TEXT,
        id_ra INTEGER
      )
    ''');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV126() => SqliteMigrations.migrateToVersion(db, 126);

  List<String> romColumns() => db
      .select('PRAGMA table_info(user_roms)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v126', () {
    test('adds ra_match_source when the column is missing', () async {
      expect(romColumns(), isNot(contains('ra_match_source')));

      await runV126();

      expect(romColumns(), contains('ra_match_source'));
    });

    test('is a no-op when the column already exists', () async {
      db.execute('ALTER TABLE user_roms ADD COLUMN ra_match_source TEXT');
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, ra_match_source) "
        "VALUES ('a.nes', '/roms/nes/a.nes', 'manual')",
      );

      await runV126();

      // A device that already has the column keeps its data untouched.
      final rows = db.select(
        "SELECT ra_match_source FROM user_roms WHERE rom_path = '/roms/nes/a.nes'",
      );
      expect(rows.first['ra_match_source'], 'manual');
      expect(
        romColumns().where((c) => c == 'ra_match_source').length,
        1,
        reason: 'the column must not be added twice',
      );
    });

    test('re-running the migration stays a no-op', () async {
      await runV126();
      await runV126();

      expect(romColumns(), contains('ra_match_source'));
    });

    test('existing rows default to a null match source', () async {
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, id_ra) "
        "VALUES ('old.nes', '/roms/nes/old.nes', 42)",
      );

      await runV126();

      // A null means "matched before this was recorded", which the write guard
      // treats as automatic and therefore replaceable.
      final rows = db.select(
        "SELECT ra_match_source FROM user_roms WHERE rom_path = '/roms/nes/old.nes'",
      );
      expect(rows.first['ra_match_source'], isNull);
    });
  });

  group('migration v127', () {
    Future<void> runV127() => SqliteMigrations.migrateToVersion(db, 127);

    test('adds ra_hash_skipped when the column is missing', () async {
      expect(romColumns(), isNot(contains('ra_hash_skipped')));

      await runV127();

      expect(romColumns(), contains('ra_hash_skipped'));
    });

    test('is a no-op when the column already exists', () async {
      db.execute('ALTER TABLE user_roms ADD COLUMN ra_hash_skipped TEXT');
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, ra_hash_skipped) "
        "VALUES ('a.nes', '/roms/nes/a.nes', 'missing')",
      );

      await runV127();

      final rows = db.select(
        "SELECT ra_hash_skipped FROM user_roms WHERE rom_path = '/roms/nes/a.nes'",
      );
      expect(rows.first['ra_hash_skipped'], 'missing');
    });
  });
}
