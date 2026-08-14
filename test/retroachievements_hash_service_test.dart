import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/retroachievements_hash_service.dart';

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
}
