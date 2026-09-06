import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v140, which adds the collections browser's own sort
/// preference (`collection_sort_by` / `collection_sort_order`) to
/// `user_config`.
///
/// The "old device" case is a `user_config` that predates both columns; the
/// migration has to add them and be a no-op when run again, because a device
/// whose DB was already past 137 when it first saw this binary would otherwise
/// never get them.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE user_config (
        id INTEGER PRIMARY KEY,
        system_view_mode TEXT DEFAULT 'grid',
        system_sort_by TEXT DEFAULT 'alphabetical',
        system_sort_order TEXT DEFAULT 'asc'
      )
    ''');
    db.execute('INSERT INTO user_config (id) VALUES (1)');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV140() => SqliteMigrations.migrateToVersion(db, 140);

  List<String> configColumns() => db
      .select('PRAGMA table_info(user_config)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v140', () {
    test('adds both collection sort columns when they are missing', () async {
      expect(configColumns(), isNot(contains('collection_sort_by')));

      await runV140();

      expect(configColumns(), contains('collection_sort_by'));
      expect(configColumns(), contains('collection_sort_order'));
    });

    test('defaults to name ascending on an existing row', () async {
      await runV140();

      final row = db.select('SELECT * FROM user_config WHERE id = 1').first;
      expect(row['collection_sort_by'], 'name');
      expect(row['collection_sort_order'], 'asc');
    });

    test('re-running is a no-op', () async {
      await runV140();
      db.execute(
        "UPDATE user_config SET collection_sort_by = 'game_count' WHERE id = 1",
      );

      await runV140();

      final row = db.select('SELECT * FROM user_config WHERE id = 1').first;
      // The second run must not re-add the column or reset the user's choice.
      expect(row['collection_sort_by'], 'game_count');
      expect(configColumns().where((c) => c == 'collection_sort_by').length, 1);
    });

    test('adds only the missing column when one already exists', () async {
      db.execute(
        "ALTER TABLE user_config ADD COLUMN collection_sort_by TEXT DEFAULT 'name'",
      );

      await runV140();

      expect(configColumns(), contains('collection_sort_order'));
      expect(configColumns().where((c) => c == 'collection_sort_by').length, 1);
    });
  });
}
