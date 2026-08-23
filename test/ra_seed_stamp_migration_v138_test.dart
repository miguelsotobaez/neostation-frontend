import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v138, which adds `user_config.ra_seed_stamp` — the
/// generation stamp of the bundled RetroAchievements seed asset currently
/// loaded into `app_ra_game_list`.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    // The "old device" case: user_config as it stands before v138.
    db.execute('''
      CREATE TABLE user_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        last_scan TEXT,
        ra_user TEXT,
        systems_version TEXT DEFAULT '',
        neostation_app_version TEXT DEFAULT ''
      )
    ''');
    db.execute(
      "INSERT INTO user_config (id, systems_version) VALUES (1, '1.2')",
    );
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV138() => SqliteMigrations.migrateToVersion(db, 138);

  List<String> configColumns() => db
      .select('PRAGMA table_info(user_config)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v138', () {
    test('adds ra_seed_stamp when the column is missing', () async {
      expect(configColumns(), isNot(contains('ra_seed_stamp')));

      await runV138();

      expect(configColumns(), contains('ra_seed_stamp'));
    });

    test('defaults the new column to the empty stamp, so the next launch '
        're-seeds once rather than trusting stale rows', () async {
      await runV138();

      final row = db.select(
        'SELECT ra_seed_stamp FROM user_config WHERE id = 1',
      );
      expect(row.first['ra_seed_stamp'], '');
    });

    test('leaves existing config values alone', () async {
      await runV138();

      final row = db.select(
        'SELECT systems_version FROM user_config WHERE id = 1',
      );
      expect(row.first['systems_version'], '1.2');
    });

    test('is a no-op when re-run', () async {
      await runV138();
      db.execute(
        "UPDATE user_config SET ra_seed_stamp = 'stamp-a' WHERE id = 1",
      );

      await runV138();

      expect(configColumns(), contains('ra_seed_stamp'));
      final row = db.select(
        'SELECT ra_seed_stamp FROM user_config WHERE id = 1',
      );
      expect(row.first['ra_seed_stamp'], 'stamp-a');
    });

    test('is a no-op on a database that already has the column', () async {
      db.execute(
        "ALTER TABLE user_config ADD COLUMN ra_seed_stamp TEXT DEFAULT ''",
      );

      await runV138();

      final matches = configColumns().where((c) => c == 'ra_seed_stamp');
      expect(matches, hasLength(1));
    });
  });
}
