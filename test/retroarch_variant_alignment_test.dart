import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';

import 'database_test_helper.dart';

/// Regression guard for RetroArch variant alignment on Android.
///
/// `app_emulators.is_default` decides which RetroArch package receives the
/// launch intent, and these two routines are the only thing keeping it pointed
/// at the variant the user actually installed. They used to skip wholesale
/// whenever *any* `is_user_default` row existed anywhere, so one deliberate
/// pick on one system froze alignment for the entire library — and the natural
/// workaround for a failing launch (choosing an emulator by hand) was itself
/// what made the breakage permanent.
void main() {
  late DatabaseTestHelper helper;
  late DatabaseAdapter db;

  const androidOsId = 2;

  setUp(() async {
    helper = DatabaseTestHelper();
    db = await helper.setUp();
    await db.execute(
      "INSERT INTO app_os (id, name) VALUES ($androidOsId, 'android')",
    );

    // Two systems, each offered by both RetroArch variants plus a standalone.
    await db.execute('''
      INSERT INTO app_emulators
        (system_id, os_id, name, unique_identifier, is_standalone,
         android_package_name, is_default, is_default_core)
      VALUES
        ('snes', $androidOsId, 'RA64 bsnes', 'snes.ra64.bsnes', 0, 'com.retroarch.aarch64', 0, 1),
        ('snes', $androidOsId, 'RA32 bsnes', 'snes.ra32.bsnes', 0, 'com.retroarch.ra32',    1, 1),
        ('snes', $androidOsId, 'Snes9x EX', 'snes.standalone.snes9x', 1, 'com.explusalpha.Snes9xPlus', 0, 0),
        ('nes',  $androidOsId, 'RA64 mesen', 'nes.ra64.mesen', 0, 'com.retroarch.aarch64', 0, 1),
        ('nes',  $androidOsId, 'RA32 mesen', 'nes.ra32.mesen', 0, 'com.retroarch.ra32',    1, 1),
        ('nes',  $androidOsId, 'Nesoid',    'nes.standalone.nesoid', 1, 'com.androidemu.nes', 0, 0)
    ''');
  });

  tearDown(() async => helper.tearDown());

  Future<List<String>> defaultsFor(String systemId) async {
    final rows = await db.rawQuery(
      'SELECT unique_identifier FROM app_emulators '
      'WHERE system_id = ? AND is_default = 1 ORDER BY unique_identifier',
      [systemId],
    );
    return rows.map((r) => r['unique_identifier'].toString()).toList();
  }

  Future<void> setUserDefault(String uid) => db.rawInsert(
    'INSERT INTO user_emulator_config (emulator_unique_id, emulator_path, is_user_default) '
    'VALUES (?, ?, 1)',
    [uid, ''],
  );

  group('fixRetroArchDefaultForAndroid', () {
    test('points systems at the installed variant', () async {
      await SqliteService.fixRetroArchDefaultForAndroid(
        'com.retroarch.aarch64',
      );

      expect(await defaultsFor('snes'), ['snes.ra64.bsnes']);
      expect(await defaultsFor('nes'), ['nes.ra64.mesen']);
    });

    test('leaves a system the user configured alone', () async {
      await setUserDefault('snes.standalone.snes9x');

      await SqliteService.fixRetroArchDefaultForAndroid(
        'com.retroarch.aarch64',
      );

      // Untouched: the user's choice governs this system.
      expect(await defaultsFor('snes'), ['snes.ra32.bsnes']);
    });

    test(
      'still repairs every other system when one is user-configured',
      () async {
        // The regression: this single row used to abort alignment globally,
        // leaving 'nes' pointed at a variant that may not be installed.
        await setUserDefault('snes.standalone.snes9x');

        await SqliteService.fixRetroArchDefaultForAndroid(
          'com.retroarch.aarch64',
        );

        expect(await defaultsFor('nes'), ['nes.ra64.mesen']);
      },
    );

    test(
      'clears a standalone default that a core default supersedes',
      () async {
        await db.rawUpdate(
          "UPDATE app_emulators SET is_default = 1 "
          "WHERE unique_identifier = 'nes.standalone.nesoid'",
        );

        await SqliteService.fixRetroArchDefaultForAndroid(
          'com.retroarch.aarch64',
        );

        expect(await defaultsFor('nes'), ['nes.ra64.mesen']);
      },
    );
  });

  group('clearRetroArchDefaultsForAndroid', () {
    test('falls back to standalone when no RetroArch is installed', () async {
      await SqliteService.clearRetroArchDefaultsForAndroid();

      expect(await defaultsFor('snes'), ['snes.standalone.snes9x']);
      expect(await defaultsFor('nes'), ['nes.standalone.nesoid']);
    });

    test('leaves a user-configured system alone but clears the rest', () async {
      await setUserDefault('snes.ra32.bsnes');

      await SqliteService.clearRetroArchDefaultsForAndroid();

      // snes keeps the user's RetroArch pick; nes still gets repaired.
      expect(await defaultsFor('snes'), ['snes.ra32.bsnes']);
      expect(await defaultsFor('nes'), ['nes.standalone.nesoid']);
    });
  });
}
