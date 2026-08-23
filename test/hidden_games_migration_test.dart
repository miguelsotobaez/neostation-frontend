import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v122, which adds `user_roms.is_hidden` — the per-game
/// hide flag behind "Hide Game" (per-game settings) and the Hidden tab of the
/// system settings dialog.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    // The pre-v122 shape of the table: no is_hidden column.
    db.execute('''
      CREATE TABLE user_roms (
        app_system_id TEXT NOT NULL,
        app_emulator_unique_id TEXT,
        app_emulator_os_id INTEGER,
        filename TEXT NOT NULL,
        rom_path TEXT NOT NULL COLLATE NOCASE,
        is_favorite INTEGER DEFAULT 0,
        play_time INTEGER DEFAULT 0,
        last_played TEXT,
        cloud_sync_enabled INTEGER DEFAULT 1,
        created_at TEXT DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        UNIQUE(rom_path)
      )
    ''');
    db.execute(
      "INSERT INTO user_roms (app_system_id, filename, rom_path, is_favorite, "
      "play_time) VALUES ('nes', 'Game.zip', '/roms/nes/Game.zip', 1, 42)",
    );
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV122() => SqliteMigrations.migrateToVersion(db, 122);

  List<String> romColumns() => db
      .select('PRAGMA table_info(user_roms)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v122', () {
    test('adds is_hidden when the column is missing', () async {
      expect(romColumns(), isNot(contains('is_hidden')));

      await runV122();

      expect(romColumns(), contains('is_hidden'));
    });

    test('defaults existing games to visible', () async {
      await runV122();

      final rows = db.select('SELECT is_hidden FROM user_roms');
      expect(rows, hasLength(1));
      expect(rows.first['is_hidden'], 0);
    });

    test('leaves the rest of the row untouched', () async {
      await runV122();

      final row = db.select('SELECT * FROM user_roms').first;
      expect(row['filename'], 'Game.zip');
      expect(row['is_favorite'], 1);
      expect(row['play_time'], 42);
    });

    test('is a no-op when is_hidden already exists', () async {
      db.execute(
        'ALTER TABLE user_roms ADD COLUMN is_hidden INTEGER DEFAULT 0',
      );
      db.execute(
        "UPDATE user_roms SET is_hidden = 1 WHERE filename = 'Game.zip'",
      );

      await runV122();

      expect(romColumns(), contains('is_hidden'));
      // Re-running must not reset what the user hid.
      expect(
        db.select('SELECT is_hidden FROM user_roms').first['is_hidden'],
        1,
      );
    });
  });
}
