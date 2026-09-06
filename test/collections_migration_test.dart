import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v139, which creates the two collections tables and the
/// reverse-lookup index on membership.
///
/// The setup deliberately gives the database only `user_roms` — the "old
/// device" case, where neither collections table exists yet.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE user_roms (
        filename TEXT,
        rom_path TEXT NOT NULL UNIQUE COLLATE NOCASE,
        app_system_id TEXT,
        is_favorite INTEGER DEFAULT 0,
        is_hidden INTEGER DEFAULT 0
      )
    ''');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV139() => SqliteMigrations.migrateToVersion(db, 139);

  List<String> tableNames() => db
      .select("SELECT name FROM sqlite_master WHERE type = 'table'")
      .map((r) => r['name'].toString())
      .toList();

  List<String> indexNames() => db
      .select("SELECT name FROM sqlite_master WHERE type = 'index'")
      .map((r) => r['name'].toString())
      .toList();

  List<String> columnsOf(String table) => db
      .select('PRAGMA table_info($table)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v139', () {
    test('creates both collections tables', () async {
      expect(tableNames(), isNot(contains('user_collections')));

      await runV139();

      expect(tableNames(), contains('user_collections'));
      expect(tableNames(), contains('user_collection_items'));
    });

    test('creates the reverse-lookup index on membership', () async {
      await runV139();

      expect(indexNames(), contains('idx_collection_items_rom'));
    });

    test('user_collections carries every documented column', () async {
      await runV139();

      expect(
        columnsOf('user_collections'),
        containsAll(<String>[
          'id',
          'name',
          'image_path',
          'color1',
          'color2',
          'sort_order',
          'created_at',
          'updated_at',
        ]),
      );
    });

    test('user_collection_items carries every documented column', () async {
      await runV139();

      expect(
        columnsOf('user_collection_items'),
        containsAll(<String>[
          'collection_id',
          'rom_path',
          'sort_order',
          'created_at',
        ]),
      );
    });

    test(
      're-running the migration is a no-op and keeps existing rows',
      () async {
        await runV139();

        db.execute(
          "INSERT INTO user_roms (filename, rom_path) VALUES ('a', '/a')",
        );
        db.execute(
          "INSERT INTO user_collections (id, name) VALUES ('abc', 'Shmups')",
        );
        db.execute(
          "INSERT INTO user_collection_items (collection_id, rom_path) "
          "VALUES ('abc', '/a')",
        );

        await runV139();

        expect(tableNames(), contains('user_collections'));
        expect(indexNames(), contains('idx_collection_items_rom'));
        expect(
          db.select('SELECT name FROM user_collections').first['name'],
          'Shmups',
        );
        expect(db.select('SELECT * FROM user_collection_items').length, 1);
      },
    );

    test('duplicate collection names are allowed', () async {
      await runV139();

      db.execute(
        "INSERT INTO user_collections (id, name) VALUES ('a', 'Co-op')",
      );
      db.execute(
        "INSERT INTO user_collections (id, name) VALUES ('b', 'Co-op')",
      );

      expect(db.select('SELECT id FROM user_collections').length, 2);
    });

    test('membership is unique per (collection, rom)', () async {
      await runV139();

      db.execute(
        "INSERT INTO user_roms (filename, rom_path) VALUES ('a', '/a')",
      );
      db.execute("INSERT INTO user_collections (id, name) VALUES ('a', 'RPG')");
      db.execute(
        "INSERT INTO user_collection_items (collection_id, rom_path) "
        "VALUES ('a', '/a')",
      );

      expect(
        () => db.execute(
          "INSERT INTO user_collection_items (collection_id, rom_path) "
          "VALUES ('a', '/a')",
        ),
        throwsA(anything),
      );
    });
  });
}
