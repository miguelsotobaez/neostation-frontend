import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v156, which adds `user_config.show_cloud_sync_icon` —
/// the switch for the cloud-save mark the game views draw beside the selected
/// game.
///
/// The default is the point of the test. The mark shipped before the setting
/// did, and it already hides itself for everyone it has nothing to report on,
/// so an upgrade that defaulted it off would silently take a live readout away
/// from the users who actually sync.
void main() {
  late Database db;

  setUp(() {
    // The "old device" case: user_config without the new column.
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE user_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        game_view_mode TEXT DEFAULT 'list',
        legend_hidden INTEGER DEFAULT 0
      )
    ''');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV156() => SqliteMigrations.migrateToVersion(db, 156);

  List<String> configColumns() => db
      .select('PRAGMA table_info(user_config)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v156', () {
    test('adds show_cloud_sync_icon when the column is missing', () async {
      expect(configColumns(), isNot(contains('show_cloud_sync_icon')));

      await runV156();

      expect(configColumns(), contains('show_cloud_sync_icon'));
    });

    test('leaves an existing row with the mark on', () async {
      db.execute('INSERT INTO user_config (id) VALUES (1)');

      await runV156();

      final rows = db.select(
        'SELECT show_cloud_sync_icon FROM user_config WHERE id = 1',
      );
      expect(
        rows.first['show_cloud_sync_icon'],
        1,
        reason: 'an upgrade must not hide a mark the user already had',
      );
    });

    test('a row inserted after the migration also defaults to on', () async {
      await runV156();
      db.execute('INSERT INTO user_config (id) VALUES (1)');

      final rows = db.select(
        'SELECT show_cloud_sync_icon FROM user_config WHERE id = 1',
      );
      expect(rows.first['show_cloud_sync_icon'], 1);
    });

    test('is a no-op when the column already exists', () async {
      db.execute(
        'ALTER TABLE user_config ADD COLUMN show_cloud_sync_icon '
        'INTEGER DEFAULT 1',
      );
      db.execute(
        'INSERT INTO user_config (id, show_cloud_sync_icon) VALUES (1, 0)',
      );

      await runV156();

      // A device that already has the column keeps the user's choice.
      final rows = db.select(
        'SELECT show_cloud_sync_icon FROM user_config WHERE id = 1',
      );
      expect(rows.first['show_cloud_sync_icon'], 0);
      expect(
        configColumns().where((c) => c == 'show_cloud_sync_icon').length,
        1,
        reason: 'the column must not be added twice',
      );
    });

    test('re-running the migration stays a no-op', () async {
      await runV156();
      await runV156();

      expect(configColumns(), contains('show_cloud_sync_icon'));
    });
  });
}
