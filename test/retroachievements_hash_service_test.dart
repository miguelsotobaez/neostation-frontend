import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/retroachievements_hash_service.dart';

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
