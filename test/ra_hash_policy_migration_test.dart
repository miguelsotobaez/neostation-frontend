import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v130, which adds `app_systems.ra_hash_algo` and
/// `app_systems.ra_hash_mode` — the per-system RetroAchievements hashing policy
/// that used to be three hardcoded lists in the hash service.
void main() {
  late Database db;

  setUp(() {
    // The "old device" case: app_systems without the policy columns.
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE app_systems (
        id TEXT PRIMARY KEY,
        folder_name TEXT NOT NULL UNIQUE,
        real_name TEXT NOT NULL,
        ra_id INTEGER,
        multidisc INTEGER NOT NULL DEFAULT 0
      )
    ''');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV130() => SqliteMigrations.migrateToVersion(db, 130);

  List<String> systemColumns() => db
      .select('PRAGMA table_info(app_systems)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v130', () {
    test('adds both policy columns when they are missing', () async {
      expect(systemColumns(), isNot(contains('ra_hash_algo')));
      expect(systemColumns(), isNot(contains('ra_hash_mode')));

      await runV130();

      expect(systemColumns(), contains('ra_hash_algo'));
      expect(systemColumns(), contains('ra_hash_mode'));
    });

    test('is a no-op when both columns already exist', () async {
      await runV130();
      final after = systemColumns();

      await runV130();

      expect(systemColumns(), after);
    });

    test('adds only the column that is missing', () async {
      db.execute('ALTER TABLE app_systems ADD COLUMN ra_hash_algo TEXT');

      await runV130();

      final columns = systemColumns();
      expect(columns.where((c) => c == 'ra_hash_algo'), hasLength(1));
      expect(columns, contains('ra_hash_mode'));
    });

    test('leaves existing rows alone — syncSystems refills them', () async {
      db.execute(
        "INSERT INTO app_systems (id, folder_name, real_name, ra_id) "
        "VALUES ('nes', 'nes', 'NES', 7)",
      );

      await runV130();

      final row = db.select('SELECT * FROM app_systems').single;
      expect(row['ra_id'], 7);
      // Null reads as the permissive default, which is what an undeclared
      // system did before the policy became data.
      expect(row['ra_hash_algo'], isNull);
      expect(row['ra_hash_mode'], isNull);
    });
  });
}
