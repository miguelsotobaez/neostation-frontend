import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v146, which adds `user_config.recent_card_size` — the
/// cell span the "Recently Played" card takes in the systems grid.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE user_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        system_view_mode TEXT DEFAULT 'grid',
        hide_recent_card INTEGER DEFAULT 0,
        legend_hidden INTEGER DEFAULT 0
      )
    ''');
    db.execute('INSERT INTO user_config (id) VALUES (1)');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV146() => SqliteMigrations.migrateToVersion(db, 146);

  List<String> configColumns() => db
      .select('PRAGMA table_info(user_config)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v146', () {
    test('adds recent_card_size when the column is missing', () async {
      await runV146();

      expect(configColumns(), contains('recent_card_size'));
    });

    test('existing rows default to the 3x2 card', () async {
      await runV146();

      final value = db
          .select('SELECT recent_card_size FROM user_config WHERE id = 1')
          .first['recent_card_size'];
      expect(value, 'default');
    });

    test('is a no-op when recent_card_size already exists', () async {
      db.execute(
        "ALTER TABLE user_config ADD COLUMN recent_card_size TEXT DEFAULT 'default'",
      );
      db.execute("UPDATE user_config SET recent_card_size = '2x1'");

      await runV146();

      expect(configColumns(), contains('recent_card_size'));
      final value = db
          .select('SELECT recent_card_size FROM user_config WHERE id = 1')
          .first['recent_card_size'];
      expect(value, '2x1', reason: 'a chosen size must survive the migration');
    });

    test('leaves the other config columns untouched', () async {
      await runV146();

      final columns = configColumns();
      expect(columns, contains('system_view_mode'));
      expect(columns, contains('hide_recent_card'));
      expect(columns, contains('legend_hidden'));
    });
  });
}
