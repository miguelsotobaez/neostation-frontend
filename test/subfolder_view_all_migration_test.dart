import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v147, which adds `user_config.subfolder_view_all` — the
/// remembered state of the global "Show Subfolders" toggle in Settings >
/// General.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    // The "old device" case: a user_config without the new column.
    db.execute('''
      CREATE TABLE user_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        scan_on_startup INTEGER DEFAULT 1,
        ignore_hidden_files INTEGER DEFAULT 1,
        ra_match_on_startup INTEGER DEFAULT 0
      )
    ''');
    db.execute('INSERT INTO user_config (id) VALUES (1)');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV147() => SqliteMigrations.migrateToVersion(db, 147);

  List<String> configColumns() => db
      .select('PRAGMA table_info(user_config)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v147', () {
    test('adds subfolder_view_all when the column is missing', () async {
      await runV147();

      expect(configColumns(), contains('subfolder_view_all'));
    });

    test('defaults the new column to off for existing rows', () async {
      await runV147();

      final row = db.select('SELECT subfolder_view_all FROM user_config').first;
      expect(row['subfolder_view_all'], 0);
    });

    test('re-running is a no-op and keeps the stored value', () async {
      await runV147();
      db.execute('UPDATE user_config SET subfolder_view_all = 1');

      await runV147();

      final row = db.select('SELECT subfolder_view_all FROM user_config').first;
      expect(row['subfolder_view_all'], 1);
    });

    test('leaves the other config columns untouched', () async {
      await runV147();

      final columns = configColumns();
      expect(columns, contains('scan_on_startup'));
      expect(columns, contains('ignore_hidden_files'));
      expect(columns, contains('ra_match_on_startup'));
    });
  });
}
