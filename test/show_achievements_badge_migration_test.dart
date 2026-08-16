import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v128, which adds `user_config.show_achievements_badge` —
/// the opt-in for the achievement count drawn on library tiles.
///
/// The default matters as much as the column: the badge only appears on ROMs
/// matched to a RetroAchievements game, so a library nothing has hashed yet
/// would show it almost nowhere. Off by default, and an upgrade must not turn
/// it on behind the user's back.
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

  Future<void> runV128() => SqliteMigrations.migrateToVersion(db, 128);

  List<String> configColumns() => db
      .select('PRAGMA table_info(user_config)')
      .map((c) => c['name'].toString())
      .toList();

  group('migration v128', () {
    test('adds show_achievements_badge when the column is missing', () async {
      expect(configColumns(), isNot(contains('show_achievements_badge')));

      await runV128();

      expect(configColumns(), contains('show_achievements_badge'));
    });

    test('leaves an existing row with the badge off', () async {
      db.execute('INSERT INTO user_config (id) VALUES (1)');

      await runV128();

      final rows = db.select(
        'SELECT show_achievements_badge FROM user_config WHERE id = 1',
      );
      expect(
        rows.first['show_achievements_badge'],
        0,
        reason: 'an upgrade must not enable the badge on its own',
      );
    });

    test('a row inserted after the migration also defaults to off', () async {
      await runV128();
      db.execute('INSERT INTO user_config (id) VALUES (1)');

      final rows = db.select(
        'SELECT show_achievements_badge FROM user_config WHERE id = 1',
      );
      expect(rows.first['show_achievements_badge'], 0);
    });

    test('is a no-op when the column already exists', () async {
      db.execute(
        'ALTER TABLE user_config ADD COLUMN show_achievements_badge '
        'INTEGER DEFAULT 0',
      );
      db.execute(
        'INSERT INTO user_config (id, show_achievements_badge) VALUES (1, 1)',
      );

      await runV128();

      // A device that already has the column keeps the user's choice.
      final rows = db.select(
        'SELECT show_achievements_badge FROM user_config WHERE id = 1',
      );
      expect(rows.first['show_achievements_badge'], 1);
      expect(
        configColumns().where((c) => c == 'show_achievements_badge').length,
        1,
        reason: 'the column must not be added twice',
      );
    });

    test('re-running the migration stays a no-op', () async {
      await runV128();
      await runV128();

      expect(configColumns(), contains('show_achievements_badge'));
    });
  });
}
