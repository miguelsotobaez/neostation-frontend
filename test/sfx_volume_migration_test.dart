import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v125, which adds `user_config.sfx_volume` — the UI
/// sound level the settings row cycles through. The migration guards the
/// `ALTER TABLE` so a database that already has the column, or one that first
/// saw this binary while already past v125, is not broken by it.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE user_config (
        id INTEGER PRIMARY KEY,
        setup_completed INTEGER DEFAULT 0,
        hide_bottom_screen INTEGER DEFAULT 0,
        sfx_enabled INTEGER DEFAULT 1,
        app_language TEXT DEFAULT 'en'
      )
    ''');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV125() => SqliteMigrations.migrateToVersion(db, 125);

  List<String> configColumns() => db
      .select('PRAGMA table_info(user_config)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v125', () {
    test('adds sfx_volume when the column is missing', () async {
      await runV125();

      expect(configColumns(), contains('sfx_volume'));
    });

    test(
      'defaults sfx_volume to the volume the app already played at',
      () async {
        db.execute('INSERT INTO user_config (id) VALUES (1)');

        await runV125();

        final row = db.select(
          'SELECT sfx_volume FROM user_config WHERE id = 1',
        );
        expect(row.first['sfx_volume'], 0.75);
      },
    );

    test('is a no-op when sfx_volume already exists', () async {
      db.execute(
        'ALTER TABLE user_config ADD COLUMN sfx_volume REAL DEFAULT 0.75',
      );

      await runV125();

      expect(configColumns(), contains('sfx_volume'));
    });

    test('leaves the other config columns untouched', () async {
      await runV125();

      final columns = configColumns();
      expect(columns, contains('sfx_enabled'));
      expect(columns, contains('setup_completed'));
      expect(columns, contains('app_language'));
    });
  });
}
