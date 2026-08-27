import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE user_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        hide_tab_sync INTEGER DEFAULT 0,
        hide_tab_search INTEGER DEFAULT 0
      );
    ''');
    db.execute('INSERT INTO user_config (id) VALUES (1);');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV150() => SqliteMigrations.migrateToVersion(db, 150);

  group('Migration v150 (Collections)', () {
    test('adds hide_tab_collections column to user_config', () async {
      await runV150();

      final columns = db
          .select('PRAGMA table_info(user_config)')
          .map((c) => c['name'].toString())
          .toSet();

      expect(columns.contains('hide_tab_collections'), isTrue);

      final row = db.select(
        'SELECT hide_tab_collections FROM user_config WHERE id = 1',
      );
      expect(row.first['hide_tab_collections'], 0);
    });

    test('creates user_collections and user_collection_roms tables', () async {
      await runV150();

      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((r) => r['name'].toString())
          .toSet();

      expect(tables.contains('user_collections'), isTrue);
      expect(tables.contains('user_collection_roms'), isTrue);
    });

    test('creates indexes for user_collection_roms', () async {
      await runV150();

      final indices = db
          .select("SELECT name FROM sqlite_master WHERE type = 'index'")
          .map((r) => r['name'].toString())
          .toSet();

      expect(
        indices.contains('idx_user_collection_roms_collection_id'),
        isTrue,
      );
      expect(indices.contains('idx_user_collection_roms_rom_path'), isTrue);
    });

    test('is idempotent when run multiple times', () async {
      await runV150();
      await runV150();

      final tables = db
          .select("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((r) => r['name'].toString())
          .toSet();

      expect(tables.contains('user_collections'), isTrue);
      expect(tables.contains('user_collection_roms'), isTrue);
    });
  });
}
