import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v108, which repairs databases holding more than one
/// `app_emulators.is_default = 1` row for the same (system_id, os_id).
///
/// The seed data (`assets/systems/*.json`) is the authority on which emulator
/// should win, and no SQL rule reproduces its choice, so v108 demotes the whole
/// offending group to 0 and lets the JSON sync re-apply the single flagged
/// emulator on the next scan.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE app_emulators (
        unique_identifier TEXT NOT NULL,
        os_id INTEGER NOT NULL,
        system_id TEXT NOT NULL,
        name TEXT,
        is_standalone INTEGER NOT NULL DEFAULT 0,
        is_default INTEGER NOT NULL DEFAULT 0
      )
    ''');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV108() => SqliteMigrations.migrateToVersion(db, 108);

  void insert(
    String uniqueId,
    int osId,
    String systemId, {
    int isDefault = 0,
    int isStandalone = 1,
  }) {
    db.execute(
      'INSERT INTO app_emulators '
      '(unique_identifier, os_id, system_id, name, is_standalone, is_default) '
      'VALUES (?, ?, ?, ?, ?, ?)',
      [uniqueId, osId, systemId, uniqueId, isStandalone, isDefault],
    );
  }

  int defaultOf(String uniqueId, int osId) {
    final rows = db.select(
      'SELECT is_default FROM app_emulators WHERE unique_identifier = ? AND os_id = ?',
      [uniqueId, osId],
    );
    return int.parse(rows.first['is_default'].toString());
  }

  test('clears both rows of a duplicated (system, os) group', () {
    // The real xbox360 case: paid vs free AX360e both flagged default.
    insert('xbox360.aenu.ax360e', 2, 'xbox360', isDefault: 1);
    insert('xbox360.aenu.ax360e.free', 2, 'xbox360', isDefault: 1);

    return runV108().then((_) {
      expect(defaultOf('xbox360.aenu.ax360e', 2), 0);
      expect(defaultOf('xbox360.aenu.ax360e.free', 2), 0);
    });
  });

  test('clears a duplicated group with more than two members', () async {
    insert('switch.dev.eden.eden_emulator', 2, 'switch', isDefault: 1);
    insert('switch.org.benjisc.android', 2, 'switch', isDefault: 1);
    insert('switch.skyline.emu', 2, 'switch', isDefault: 1);
    insert('switch.com.miHoYo.Yuanshen', 2, 'switch');

    await runV108();

    final remaining = db.select(
      "SELECT COUNT(*) as c FROM app_emulators WHERE system_id = 'switch' AND is_default = 1",
    );
    expect(remaining.first['c'], 0);
  });

  test('leaves a healthy single-default group untouched', () async {
    insert('snes.ra64.snes9x', 2, 'snes', isDefault: 1, isStandalone: 0);
    insert('snes.ra32.snes9x', 2, 'snes', isStandalone: 0);

    await runV108();

    expect(defaultOf('snes.ra64.snes9x', 2), 1);
    expect(defaultOf('snes.ra32.snes9x', 2), 0);
  });

  test('does not touch other systems that share the same os', () async {
    insert('xbox360.aenu.ax360e', 2, 'xbox360', isDefault: 1);
    insert('xbox360.aenu.ax360e.free', 2, 'xbox360', isDefault: 1);
    insert('psp.ppsspp', 2, 'psp', isDefault: 1);

    await runV108();

    expect(defaultOf('psp.ppsspp', 2), 1);
    expect(defaultOf('xbox360.aenu.ax360e', 2), 0);
  });

  test('scopes the repair per os — a healthy os keeps its default', () async {
    // Android is broken, Windows has a single legitimate default.
    insert('xbox360.aenu.ax360e', 2, 'xbox360', isDefault: 1);
    insert('xbox360.aenu.ax360e.free', 2, 'xbox360', isDefault: 1);
    insert('xbox360.xenia', 1, 'xbox360', isDefault: 1);

    await runV108();

    expect(defaultOf('xbox360.xenia', 1), 1);
    expect(defaultOf('xbox360.aenu.ax360e', 2), 0);
    expect(defaultOf('xbox360.aenu.ax360e.free', 2), 0);
  });

  test('is idempotent — a second run changes nothing', () async {
    insert('xbox360.aenu.ax360e', 2, 'xbox360', isDefault: 1);
    insert('xbox360.aenu.ax360e.free', 2, 'xbox360', isDefault: 1);
    insert('psp.ppsspp', 2, 'psp', isDefault: 1);

    await runV108();
    await runV108();

    expect(defaultOf('psp.ppsspp', 2), 1);
    expect(defaultOf('xbox360.aenu.ax360e', 2), 0);
    expect(defaultOf('xbox360.aenu.ax360e.free', 2), 0);
  });

  test('tolerates a database without an app_emulators table', () async {
    db.execute('DROP TABLE app_emulators');
    await expectLater(runV108(), completes);
  });
}
