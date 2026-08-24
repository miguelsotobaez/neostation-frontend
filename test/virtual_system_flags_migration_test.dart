import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v149, which clears the per-system flags that the systems
/// owning no ROM folder of their own can no longer set: "Show Subfolders" on
/// 'all' / 'favorites' / 'music' / 'android', and "Recursive Scan" on the first
/// three. Earlier builds offered those switches, so a user who flipped one left
/// a row behind that nothing reads.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE app_systems (
        id TEXT PRIMARY KEY,
        real_name TEXT,
        folder_name TEXT
      )
    ''');
    db.execute('''
      CREATE TABLE user_system_settings (
        app_system_id TEXT PRIMARY KEY,
        recursive_scan INTEGER DEFAULT 1,
        subfolder_view INTEGER DEFAULT 0,
        hide_extension INTEGER DEFAULT 0,
        updated_at TEXT
      )
    ''');
    for (final id in ['nes', 'psx', 'all', 'favorites', 'music', 'android']) {
      db.execute(
        'INSERT INTO app_systems (id, real_name, folder_name) '
        'VALUES (?, ?, ?)',
        [id, id.toUpperCase(), id],
      );
    }
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV149() => SqliteMigrations.migrateToVersion(db, 149);

  /// Writes the state an older build could leave behind: both switches flipped.
  void seedFlags(String systemId, {int recursive = 0, int subfolder = 1}) {
    db.execute(
      'INSERT INTO user_system_settings '
      '(app_system_id, recursive_scan, subfolder_view, hide_extension) '
      'VALUES (?, ?, ?, 1)',
      [systemId, recursive, subfolder],
    );
  }

  Map<String, Object?> flagsFor(String systemId) => db.select(
    'SELECT * FROM user_system_settings WHERE app_system_id = ?',
    [systemId],
  ).first;

  group('migration v149', () {
    test(
      'clears subfolder_view on every system that cannot browse a tree',
      () async {
        for (final id in ['all', 'favorites', 'music', 'android']) {
          seedFlags(id);
        }

        await runV149();

        for (final id in ['all', 'favorites', 'music', 'android']) {
          expect(flagsFor(id)['subfolder_view'], 0, reason: id);
        }
      },
    );

    test(
      'resets recursive_scan on the systems that own no ROM folder',
      () async {
        for (final id in ['all', 'favorites', 'android']) {
          seedFlags(id);
        }

        await runV149();

        for (final id in ['all', 'favorites', 'android']) {
          expect(flagsFor(id)['recursive_scan'], 1, reason: id);
        }
      },
    );

    test('leaves recursive_scan on music, which owns a real folder', () async {
      seedFlags('music');

      await runV149();

      expect(flagsFor('music')['recursive_scan'], 0);
    });

    test('leaves real systems alone', () async {
      seedFlags('nes');
      seedFlags('psx', recursive: 1, subfolder: 1);

      await runV149();

      expect(flagsFor('nes')['recursive_scan'], 0);
      expect(flagsFor('nes')['subfolder_view'], 1);
      expect(flagsFor('psx')['subfolder_view'], 1);
    });

    test('keeps the naming settings the user did choose', () async {
      seedFlags('favorites');

      await runV149();

      expect(flagsFor('favorites')['hide_extension'], 1);
    });

    test('re-running is a no-op', () async {
      seedFlags('favorites');

      await runV149();
      await runV149();

      expect(flagsFor('favorites')['subfolder_view'], 0);
      expect(flagsFor('favorites')['recursive_scan'], 1);
    });

    test('survives a database that has neither table', () async {
      db.execute('DROP TABLE user_system_settings');

      await expectLater(runV149(), completes);
    });
  });
}
