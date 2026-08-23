import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v141, which adds `user_config.ra_match_on_startup` —
/// the opt-in for running the RetroAchievements match pass after the startup
/// scan.
///
/// The default is the point of the test as much as the column is. The first
/// pass on a library that has never been matched hashes every ROM and takes
/// minutes; an upgrade that switched that on by itself would look like the app
/// hanging on launch.
///
/// The slot number is not sequential — 139 and 140 belong to an unmerged
/// branch. Sharing a number with different contents is the failure this
/// codebase has hit before: the device is already past that version, so the
/// `case` never runs and the column silently never arrives.
void main() {
  late Database db;

  setUp(() {
    // The "old device" case: user_config without the new column.
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE user_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        game_view_mode TEXT DEFAULT 'list',
        scan_on_startup INTEGER DEFAULT 1
      )
    ''');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV141() => SqliteMigrations.migrateToVersion(db, 141);

  List<String> configColumns() => db
      .select('PRAGMA table_info(user_config)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v141', () {
    test('adds ra_match_on_startup when the column is missing', () async {
      expect(configColumns(), isNot(contains('ra_match_on_startup')));

      await runV141();

      expect(configColumns(), contains('ra_match_on_startup'));
    });

    test('leaves an existing row with the startup pass off', () async {
      db.execute('INSERT INTO user_config (id) VALUES (1)');

      await runV141();

      final rows = db.select(
        'SELECT ra_match_on_startup FROM user_config WHERE id = 1',
      );
      expect(
        rows.first['ra_match_on_startup'],
        0,
        reason: 'an upgrade must not start hashing the library on its own',
      );
    });

    test('a row inserted after the migration also defaults to off', () async {
      await runV141();
      db.execute('INSERT INTO user_config (id) VALUES (1)');

      final rows = db.select(
        'SELECT ra_match_on_startup FROM user_config WHERE id = 1',
      );
      expect(rows.first['ra_match_on_startup'], 0);
    });

    test('is a no-op when the column already exists', () async {
      db.execute(
        'ALTER TABLE user_config ADD COLUMN ra_match_on_startup '
        'INTEGER DEFAULT 0',
      );
      db.execute(
        'INSERT INTO user_config (id, ra_match_on_startup) VALUES (1, 1)',
      );

      await runV141();

      // A device that already has the column keeps the user's choice.
      final rows = db.select(
        'SELECT ra_match_on_startup FROM user_config WHERE id = 1',
      );
      expect(rows.first['ra_match_on_startup'], 1);
      expect(
        configColumns().where((c) => c == 'ra_match_on_startup').length,
        1,
        reason: 'the column must not be added twice',
      );
    });

    test('re-running the migration stays a no-op', () async {
      await runV141();
      await runV141();

      expect(configColumns(), contains('ra_match_on_startup'));
    });
  });
}
