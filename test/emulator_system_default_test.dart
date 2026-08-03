import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';

import 'database_test_helper.dart';

/// Regression guard for the "system default emulator" invariant: at most ONE
/// emulator per system may carry `user_emulator_config.is_user_default = 1`.
///
/// `getUserDefaultEmulatorForSystem` reads that flag with a `LIMIT 1`, so a
/// second flagged row makes the resolved default non-deterministic — and in
/// practice the *oldest* selection wins. That is what made a deliberately
/// chosen standalone (melonDS) boot a RetroArch core, and a SNES system
/// switched from Beetle to bsnes keep launching Beetle.
void main() {
  group('migration v105 collapses duplicate system defaults', () {
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
      db.execute('''
        CREATE TABLE user_emulator_config (
          emulator_unique_id TEXT PRIMARY KEY,
          emulator_path TEXT,
          is_user_default INTEGER,
          updated_at TEXT
        )
      ''');
      db.execute('''
        INSERT INTO app_emulators
          (unique_identifier, os_id, system_id, name, is_standalone, is_default)
        VALUES
          ('ds.ra.melonds', 2, 'ds', 'RetroArch MelonDS', 0, 1),
          ('ds.standalone.melondual', 2, 'ds', 'melonDS Dual', 1, 0),
          ('snes.ra.beetle', 2, 'snes', 'Beetle SNES', 0, 1),
          ('snes.ra.bsnes', 2, 'snes', 'bsnes HD Beta', 0, 0)
      ''');
    });

    tearDown(() => db.close());

    List<String> defaultsFor(String systemId) {
      final rows = db.select(
        '''
        SELECT uc.emulator_unique_id AS uid
        FROM user_emulator_config uc
        JOIN app_emulators e ON e.unique_identifier = uc.emulator_unique_id
        WHERE uc.is_user_default = 1 AND e.system_id = ?
        ''',
        [systemId],
      );
      return rows.map((r) => r['uid'].toString()).toList();
    }

    Future<void> runV105() => SqliteMigrations.migrateToVersion(db, 105);

    test(
      'keeps the most recent pick when a core and a standalone conflict',
      () async {
        // The NDS report: a core was chosen first, then a standalone. Both rows
        // stayed flagged because setDefaultCore never cleared its own marker.
        db.execute('''
        INSERT INTO user_emulator_config VALUES
          ('ds.ra.melonds', '', 1, '2026-01-01T00:00:00.000'),
          ('ds.standalone.melondual', '', 1, '2026-02-01T00:00:00.000')
      ''');

        await runV105();

        expect(defaultsFor('ds'), ['ds.standalone.melondual']);
      },
    );

    test('keeps the most recent pick when two cores conflict', () async {
      // The SNES report: Beetle first, then bsnes HD Beta.
      db.execute('''
        INSERT INTO user_emulator_config VALUES
          ('snes.ra.beetle', '', 1, '2026-01-01T00:00:00.000'),
          ('snes.ra.bsnes', '', 1, '2026-03-01T00:00:00.000')
      ''');

      await runV105();

      expect(defaultsFor('snes'), ['snes.ra.bsnes']);
    });

    test('collapses each system independently', () async {
      db.execute('''
        INSERT INTO user_emulator_config VALUES
          ('ds.ra.melonds', '', 1, '2026-01-01T00:00:00.000'),
          ('ds.standalone.melondual', '', 1, '2026-02-01T00:00:00.000'),
          ('snes.ra.beetle', '', 1, '2026-01-01T00:00:00.000'),
          ('snes.ra.bsnes', '', 1, '2026-03-01T00:00:00.000')
      ''');

      await runV105();

      expect(defaultsFor('ds'), ['ds.standalone.melondual']);
      expect(defaultsFor('snes'), ['snes.ra.bsnes']);
    });

    test('leaves a healthy single default untouched', () async {
      db.execute('''
        INSERT INTO user_emulator_config VALUES
          ('ds.standalone.melondual', '', 1, '2026-02-01T00:00:00.000')
      ''');

      await runV105();

      expect(defaultsFor('ds'), ['ds.standalone.melondual']);
    });

    test('leaves orphaned config rows alone', () async {
      // No app_emulators row, so it belongs to no system and cannot be part of
      // a per-system conflict. Clearing it would be collateral damage.
      db.execute('''
        INSERT INTO user_emulator_config VALUES
          ('ra', '/usr/bin/retroarch', 1, '2026-01-01T00:00:00.000')
      ''');

      await runV105();

      final row = db.select(
        "SELECT is_user_default FROM user_emulator_config WHERE emulator_unique_id = 'ra'",
      );
      expect(row.first['is_user_default'], 1);
    });
  });

  group('setters keep the system default single-valued', () {
    final dbHelper = DatabaseTestHelper();
    late dynamic db;
    late int osId;

    setUp(() async {
      db = await dbHelper.setUp();
      await db.execute(
        "INSERT OR IGNORE INTO app_os (id, name) VALUES (1, 'windows'), (2, 'android'), (3, 'linux'), (4, 'macos')",
      );
      final osRow = await db.rawQuery('SELECT id FROM app_os WHERE name = ?', [
        SqliteService.getCurrentOs(),
      ]);
      osId = int.parse(osRow.first['id'].toString());

      await db.execute(
        "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('ds', 'Nintendo DS', 'ds')",
      );
      await db.execute(
        'INSERT INTO app_emulators (system_id, os_id, name, unique_identifier, is_standalone, core_filename, is_default) VALUES '
        "('ds', $osId, 'RetroArch MelonDS', 'ds.ra.melonds', 0, 'melonds_libretro.so', 1), "
        "('ds', $osId, 'RetroArch DeSmuME', 'ds.ra.desmume', 0, 'desmume_libretro.so', 0), "
        "('ds', $osId, 'melonDS Dual', 'ds.standalone.melondual', 1, NULL, 0)",
      );
    });

    tearDown(() async {
      await dbHelper.tearDown();
    });

    Future<List<String>> flaggedDefaults() async {
      final rows = await db.rawQuery('''
        SELECT uc.emulator_unique_id AS uid
        FROM user_emulator_config uc
        JOIN app_emulators e ON e.unique_identifier = uc.emulator_unique_id
        WHERE uc.is_user_default = 1 AND e.system_id = 'ds'
      ''');
      return rows.map<String>((r) => r['uid'].toString()).toList();
    }

    test('core then standalone leaves only the standalone flagged', () async {
      await SqliteService.setDefaultCore('ds', 'ds.ra.melonds', osId);
      await SqliteService.setDefaultStandaloneEmulator(
        'ds',
        'ds.standalone.melondual',
      );

      expect(await flaggedDefaults(), ['ds.standalone.melondual']);

      final resolved = await SqliteService.getUserDefaultEmulatorForSystem(
        'ds',
      );
      expect(resolved?.uniqueId, 'ds.standalone.melondual');
    });

    test('standalone then core leaves only the core flagged', () async {
      await SqliteService.setDefaultStandaloneEmulator(
        'ds',
        'ds.standalone.melondual',
      );
      await SqliteService.setDefaultCore('ds', 'ds.ra.melonds', osId);

      expect(await flaggedDefaults(), ['ds.ra.melonds']);

      final resolved = await SqliteService.getUserDefaultEmulatorForSystem(
        'ds',
      );
      expect(resolved?.uniqueId, 'ds.ra.melonds');
    });

    test('core then a different core leaves only the newest flagged', () async {
      await SqliteService.setDefaultCore('ds', 'ds.ra.melonds', osId);
      await SqliteService.setDefaultCore('ds', 'ds.ra.desmume', osId);

      expect(await flaggedDefaults(), ['ds.ra.desmume']);

      final resolved = await SqliteService.getUserDefaultEmulatorForSystem(
        'ds',
      );
      expect(resolved?.uniqueId, 'ds.ra.desmume');
    });

    test('choosing a standalone clears the core is_default flag', () async {
      await SqliteService.setDefaultStandaloneEmulator(
        'ds',
        'ds.standalone.melondual',
      );

      final rows = await db.rawQuery(
        "SELECT unique_identifier FROM app_emulators WHERE system_id = 'ds' AND is_default = 1",
      );
      expect(rows, isEmpty);
    });

    group('launch-time normalization', () {
      Future<void> normalize() =>
          SqliteService.normalizeEmulatorDefaultsForTesting(db);

      Future<List<String>> appDefaults() async {
        final rows = await db.rawQuery(
          "SELECT unique_identifier AS uid FROM app_emulators WHERE system_id = 'ds' AND is_default = 1",
        );
        return rows.map<String>((r) => r['uid'].toString()).toList();
      }

      test('never invents a user default', () async {
        // The normalizer used to write is_user_default itself, making a guess
        // indistinguishable from a deliberate choice — and the choice is what
        // wins outright at launch.
        await db.execute(
          "UPDATE app_emulators SET is_default = 0 WHERE system_id = 'ds'",
        );

        await normalize();

        expect(await flaggedDefaults(), isEmpty);
      });

      test('preserves a user-selected standalone across launches', () async {
        // Regression: the old PS1 branch cleared exactly this on every launch.
        await SqliteService.setDefaultStandaloneEmulator(
          'ds',
          'ds.standalone.melondual',
        );

        await normalize();
        await normalize();

        expect(await flaggedDefaults(), ['ds.standalone.melondual']);
        final resolved = await SqliteService.getUserDefaultEmulatorForSystem(
          'ds',
        );
        expect(resolved?.uniqueId, 'ds.standalone.melondual');
      });

      test('drops an app default that contradicts the user choice', () async {
        await db.execute(
          "UPDATE app_emulators SET is_default = 1 WHERE unique_identifier = 'ds.ra.melonds'",
        );
        await db.execute(
          "INSERT INTO user_emulator_config (emulator_unique_id, emulator_path, is_user_default) "
          "VALUES ('ds.standalone.melondual', '', 1)",
        );

        await normalize();

        expect(await appDefaults(), isEmpty);
        expect(await flaggedDefaults(), ['ds.standalone.melondual']);
      });

      test('leaves an existing app default alone', () async {
        await normalize();

        expect(await appDefaults(), ['ds.ra.melonds']);
      });

      test('seeds an app default when the system has none', () async {
        await db.execute(
          "UPDATE app_emulators SET is_default = 0 WHERE system_id = 'ds'",
        );

        await normalize();

        expect(await appDefaults(), hasLength(1));
      });

      /// A system whose only emulators are standalones — switch and xbox360
      /// are the real ones. `defaultUid` is the pick the systems JSON makes,
      /// which is deliberately *not* the alphabetically first entry.
      Future<void> seedAllStandaloneSystem({required String defaultUid}) async {
        await db.execute(
          "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('xbox360', 'Xbox 360', 'xbox360')",
        );
        for (final emu in [
          ('AX360e', 'xbox360.aenu.ax360e'),
          ('AX360e (Free)', 'xbox360.aenu.ax360e.free'),
          ('X360 Mobile', 'xbox360.x360mobile'),
          ('Xendroid', 'xbox360.xendroid'),
        ]) {
          await db.execute(
            'INSERT INTO app_emulators (system_id, os_id, name, unique_identifier, is_standalone, is_default) '
            "VALUES ('xbox360', $osId, '${emu.$1}', '${emu.$2}', 1, "
            '${emu.$2 == defaultUid ? 1 : 0})',
          );
        }
      }

      Future<List<String>> xbox360Defaults() async {
        final rows = await db.rawQuery(
          "SELECT unique_identifier AS uid FROM app_emulators "
          "WHERE system_id = 'xbox360' AND is_default = 1 ORDER BY uid",
        );
        return rows.map<String>((r) => r['uid'].toString()).toList();
      }

      test('leaves an existing standalone app default alone', () async {
        // Regression: the designation check only looked at cores, so a system
        // with nothing but standalones read as undesignated and got seeded
        // again — every launch, next to the default already there. Two winners
        // for one (system, os) makes the launch target a coin flip, which is
        // how xbox360 started booting the paid AX360e instead of the free
        // build the systems JSON picks.
        await seedAllStandaloneSystem(defaultUid: 'xbox360.aenu.ax360e.free');

        await normalize();
        await normalize();

        expect(await xbox360Defaults(), ['xbox360.aenu.ax360e.free']);
      });

      test('still seeds an all-standalone system that has no default', () async {
        // The other half: with no designation at all, seeding must still fire,
        // or the system launches nothing.
        await seedAllStandaloneSystem(defaultUid: 'none');

        await normalize();

        expect(await xbox360Defaults(), hasLength(1));
      });

      test('does not touch other operating systems', () async {
        final otherOs = osId == 2 ? 1 : 2;
        await db.execute(
          'INSERT INTO app_emulators (system_id, os_id, name, unique_identifier, is_standalone, is_default) '
          "VALUES ('ds', $otherOs, 'Other OS core', 'ds.other.core', 0, 1)",
        );
        // A user choice on the current OS previously triggered a cross-OS wipe.
        await SqliteService.setDefaultStandaloneEmulator(
          'ds',
          'ds.standalone.melondual',
        );

        await normalize();

        final rows = await db.rawQuery(
          "SELECT is_default FROM app_emulators WHERE unique_identifier = 'ds.other.core'",
        );
        expect(rows.first['is_default'], 1);
      });
    });
  });
}
