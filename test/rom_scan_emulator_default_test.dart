import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_database_service.dart';
import 'package:neostation/models/system_model.dart';

import 'database_test_helper.dart';

/// Regression guard: scanning ROMs must leave the per-game emulator columns
/// NULL ("inherit the system default"), NOT freeze the system default into
/// every row. Freezing the default is what made per-game emulator settings
/// stale/"whack-a-mole".
void main() {
  final dbHelper = DatabaseTestHelper();
  late dynamic db;

  setUp(() async {
    db = await dbHelper.setUp();
    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('snes', 'Super Nintendo', 'snes')",
    );
    await db.execute(
      "INSERT INTO app_system_extensions (system_id, extension) VALUES ('snes', 'smc')",
    );
    // A system default core EXISTS — the scan must still not stamp it.
    await db.execute(
      "INSERT INTO app_emulators (system_id, os_id, name, unique_identifier, is_standalone, is_default, is_ra_compatible) "
      "VALUES ('snes', 1, 'Snes9x', 'snes.ra.snes9x', 0, 1, 1)",
    );
  });

  tearDown(() async {
    await dbHelper.tearDown();
  });

  test(
    'scanned rows inherit (NULL emulator) instead of the stamped default',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'neostation_emu_scan_',
      );
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final snesDir = Directory('${root.path}/snes')
        ..createSync(recursive: true);
      File('${snesDir.path}/mario.smc').writeAsStringSync('ok');

      final system = SystemModel(
        id: 'snes',
        realName: 'Super Nintendo',
        folderName: 'snes',
        iconImage: '',
        color: '#000000',
        recursiveScan: true,
      );

      await SqliteDatabaseService.scanSystemRoms(system, [root.path]);

      final rows = await db.rawQuery(
        "SELECT app_emulator_unique_id, app_emulator_os_id FROM user_roms WHERE app_system_id = 'snes'",
      );

      expect(rows, hasLength(1));
      expect(rows.first['app_emulator_unique_id'], isNull);
      expect(rows.first['app_emulator_os_id'], isNull);
    },
  );
}
