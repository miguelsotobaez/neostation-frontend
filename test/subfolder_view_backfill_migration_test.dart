import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v118, which backfills
/// `user_system_settings.subfolder_view` on databases that skipped main's
/// v111/v113 because this branch claimed those version numbers for NeoSync.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE user_system_settings (
        app_system_id TEXT PRIMARY KEY,
        recursive_scan INTEGER DEFAULT 1,
        hide_extension INTEGER DEFAULT 1,
        hide_parentheses INTEGER DEFAULT 1,
        hide_brackets INTEGER DEFAULT 1,
        hide_logo INTEGER DEFAULT 0,
        prefer_file_name INTEGER DEFAULT 0,
        custom_background_path TEXT,
        custom_logo_path TEXT,
        updated_at TEXT
      )
    ''');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV118() => SqliteMigrations.migrateToVersion(db, 118);

  List<String> settingsColumns() => db
      .select('PRAGMA table_info(user_system_settings)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v118', () {
    test('adds subfolder_view when the column is missing', () async {
      await runV118();

      expect(settingsColumns(), contains('subfolder_view'));
    });

    test('is a no-op when subfolder_view already exists', () async {
      db.execute(
        'ALTER TABLE user_system_settings ADD COLUMN subfolder_view INTEGER DEFAULT 0',
      );

      await runV118();

      expect(settingsColumns(), contains('subfolder_view'));
    });

    test('leaves other settings columns untouched', () async {
      await runV118();

      final columns = settingsColumns();
      expect(columns, contains('recursive_scan'));
      expect(columns, contains('hide_extension'));
      expect(columns, contains('custom_background_path'));
    });

    test('a missing user_system_settings table does not throw', () async {
      db.execute('DROP TABLE user_system_settings');

      await expectLater(runV118(), throwsA(anything));
    });
  });
}
