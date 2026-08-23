import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/retroachievements_hash_service.dart';
import 'package:neostation/utils/disc/ra_disc_hash.dart';

import 'database_test_helper.dart';

void main() {
  group('RetroAchievementsHashService.isDiscContainer', () {
    test('recognises disc images the bulk pass must not hash whole', () {
      for (final path in const [
        '/roms/ps1/Game.chd',
        '/roms/ps1/Game.cue',
        '/roms/dc/Game.gdi',
        '/roms/psp/Game.cso',
        '/roms/gc/Game.rvz',
        '/roms/ps1/Game.m3u',
      ]) {
        expect(
          RetroAchievementsHashService.isDiscContainer(path),
          isTrue,
          reason: path,
        );
      }
    });

    test('leaves cartridge dumps alone', () {
      for (final path in const [
        '/roms/nes/Game.nes',
        '/roms/md/Game.bin',
        '/roms/snes/Game.zip',
        '/roms/gba/Game.gba',
      ]) {
        expect(
          RetroAchievementsHashService.isDiscContainer(path),
          isFalse,
          reason: path,
        );
      }
    });

    test('handles Android SAF content URIs', () {
      // Android ROM paths arrive URL-encoded; only the separators are escaped,
      // so the extension is still readable at the end of the URI.
      expect(
        RetroAchievementsHashService.isDiscContainer(
          'content://com.android.externalstorage.documents/document/primary%3Aemu%2Froms%2Fps1%2FGame.chd',
        ),
        isTrue,
      );
      expect(
        RetroAchievementsHashService.isDiscContainer(
          'content://com.android.externalstorage.documents/document/primary%3Aemu%2Froms%2Fnes%2FGame.nes',
        ),
        isFalse,
      );
    });

    test('is case-insensitive', () {
      expect(
        RetroAchievementsHashService.isDiscContainer('/roms/ps1/GAME.CHD'),
        isTrue,
      );
    });
  });

  group('containers the disc reader can open', () {
    test('recognises the ones it reads', () {
      for (final path in const [
        '/roms/ps1/Game.chd',
        '/roms/ps1/Game.cue',
        '/roms/ps2/Game.iso',
        '/roms/ps1/Game.m3u',
        '/roms/psp/Game.pbp',
        '/roms/ps1/GAME.CHD',
      ]) {
        expect(RaDiscHash.canHash(path), isTrue, reason: path);
      }
    });

    test('rejects the ones it does not, so they are parked not guessed', () {
      // A container this cannot open must be recorded as unhashable rather
      // than hashed some other way, which would produce something
      // RetroAchievements never registered.
      for (final path in const [
        '/roms/dc/Game.gdi',
        '/roms/dc/Game.cdi',
        '/roms/psp/Game.cso',
        '/roms/gc/Game.rvz',
      ]) {
        expect(RaDiscHash.canHash(path), isFalse, reason: path);
      }
    });
  });

  group('a disc system reaches the pass', () {
    final dbHelper = DatabaseTestHelper();
    late dynamic db;

    setUp(() async {
      db = await dbHelper.setUp();
      await db.execute(
        "INSERT INTO app_systems (id, real_name, folder_name, ra_id, multidisc)"
        " VALUES ('ps1', 'PlayStation', 'ps1', '12', 1)",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id) "
        "VALUES ('Game.chd', '/roms/ps1/Game.chd', 'ps1')",
      );
    });

    tearDown(() async {
      await dbHelper.tearDown();
    });

    test('is walked once it declares a disc algorithm', () async {
      await db.execute(
        "UPDATE app_systems SET ra_hash_algo = 'psx', "
        "ra_hash_mode = 'hash_only' WHERE id = 'ps1'",
      );

      final result = await RetroAchievementsHashService.rematchLibrary();

      expect(result.total, 1);
      // The file is not there, so it parks — but as a missing file, which is
      // the truth, rather than as a disc image nothing can hash.
      final row = await db.rawQuery(
        "SELECT ra_hash_skipped FROM user_roms WHERE filename = 'Game.chd'",
      );
      expect(row.first['ra_hash_skipped'], 'missing');
    });

    test('is left out while it declares none', () async {
      final result = await RetroAchievementsHashService.rematchLibrary();

      expect(result.total, 0);
    });
  });

  // The reopen is right for a pass the user asked for and wrong for one that
  // runs by itself: on a fully matched library it re-reads every unhashable
  // ROM on every single launch, always failing, forever.
  group('reopening ROMs parked as unhashable', () {
    final dbHelper = DatabaseTestHelper();
    late dynamic db;

    setUp(() async {
      db = await dbHelper.setUp();
      await db.execute(
        "INSERT INTO app_systems (id, real_name, folder_name, ra_id, multidisc)"
        " VALUES ('nes', 'NES', 'nes', '7', 0)",
      );
      // Parked by an earlier run: no hash, and a skip reason recorded.
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, "
        "ra_hash_skipped) VALUES ('Game.nes', '/roms/nes/Game.nes', 'nes', "
        "'missing')",
      );
    });

    tearDown(() async {
      await dbHelper.tearDown();
    });

    test('a pass the user asked for retries them', () async {
      final result = await RetroAchievementsHashService.rematchLibrary();

      expect(
        result.total,
        1,
        reason: 'the parked ROM should be reopened and walked again',
      );
      // Still missing, so it parks again — but it got its retry, which is the
      // point: the user may have restored the file since.
      expect(result.skipped, 1);
    });

    test('an automatic pass leaves them parked', () async {
      final result = await RetroAchievementsHashService.rematchLibrary(
        reopenSkipped: false,
      );

      expect(
        result.total,
        0,
        reason: 'an unattended pass must not re-read unhashable files',
      );
      final row = await db.rawQuery(
        "SELECT ra_hash_skipped FROM user_roms WHERE filename = 'Game.nes'",
      );
      expect(
        row.first['ra_hash_skipped'],
        'missing',
        reason: 'the skip marker must survive, or the next run walks it again',
      );
    });

    test(
      'an automatic pass still hashes ROMs that were never parked',
      () async {
        await db.execute(
          "INSERT INTO user_roms (filename, rom_path, app_system_id) "
          "VALUES ('New.nes', '/roms/nes/New.nes', 'nes')",
        );

        final result = await RetroAchievementsHashService.rematchLibrary(
          reopenSkipped: false,
        );

        expect(
          result.total,
          1,
          reason: 'skipping the reopen must not skip genuinely new ROMs',
        );
      },
    );
  });

  group('the library pass is a singleton', () {
    final dbHelper = DatabaseTestHelper();

    setUp(() async {
      await dbHelper.setUp();
    });

    tearDown(() async {
      await dbHelper.tearDown();
    });

    // The pass outlives the Tools screen. If "is it running" lived in that
    // widget it would read idle after navigating away and back, and a second
    // concurrent pass would race the first over the same rows.
    test('nothing is running before one starts', () {
      expect(RetroAchievementsHashService.isRematchRunning, isFalse);
    });

    test('a pause request while idle is a no-op, not latched state', () async {
      RetroAchievementsHashService.requestRematchPause();

      // If the request had latched, the next real pass would abort instantly.
      expect(RetroAchievementsHashService.isRematchRunning, isFalse);
      final result = await RetroAchievementsHashService.rematchLibrary(
        mode: RaRematchMode.lookupOnly,
      );
      expect(
        result.cancelled,
        isFalse,
        reason: 'a stale pause must not cancel the next run',
      );
    });

    test('the running flag is cleared once the pass returns', () async {
      await RetroAchievementsHashService.rematchLibrary(
        mode: RaRematchMode.lookupOnly,
      );
      expect(
        RetroAchievementsHashService.isRematchRunning,
        isFalse,
        reason: 'a flag left set would make the tool unstartable forever',
      );
    });
  });
}
