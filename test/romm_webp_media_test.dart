import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/providers/file_provider.dart';
import 'package:neostation/services/romm_service.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

import 'database_test_helper.dart';

/// RomM stores every cover as `big.png` whatever the source served, so a cover
/// import can come back holding WebP bytes (SteamGridDB and LaunchBox both
/// serve it). Saved under its true `.webp` name, that art was downloaded
/// correctly and then invisible: the library's lookup only ever probed
/// `.png`/`.jpg`, so the game showed no box art while the file sat on disk —
/// which is what issue #355 reported.
///
/// Two halves of the fix are covered here: art already on disk from a 0.10.0
/// import resolves, and a body that isn't an image at all is refused rather
/// than written out as art.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const game = GameModel(
    romname: 'Adventure Island II (USA, Europe).gb',
    realname: 'Adventure Island II',
    name: 'Adventure Island II',
    year: '1991',
    developer: '',
    publisher: '',
    genre: '',
    players: '1',
    rating: 0,
    systemId: 'gb',
    systemFolderName: 'gb',
  );

  group('media lookup', () {
    final dbHelper = DatabaseTestHelper();
    late Directory tempDir;
    late FileProvider provider;

    setUp(() async {
      final db = await dbHelper.setUp();
      tempDir = await Directory.systemTemp.createTemp('neostation_webp_test');

      SharedPreferences.setMockInitialValues({
        'custom_user_data_path': tempDir.path,
      });

      await db.execute(
        "INSERT INTO app_systems (id, real_name, folder_name, screenscraper_id) "
        "VALUES ('gb', 'Game Boy', 'gb', 9)",
      );

      provider = FileProvider();
      await provider.initialize();
      expect(provider.isInitialized, isTrue);
    });

    tearDown(() async {
      await dbHelper.tearDown();
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    /// Writes [name] into the ROM's `box2d` folder and returns it.
    Future<File> writeBox2d(String name) async {
      final file = File(path.join(tempDir.path, 'media', 'gb', 'box2d', name));
      await file.parent.create(recursive: true);
      await file.writeAsString('art');
      return file;
    }

    test(
      'resolves a .webp cover left behind by an older RomM import',
      () async {
        final webp = await writeBox2d('Adventure Island II (USA, Europe).webp');

        expect(game.getImagePath('gb', 'box2d', provider), webp.path);
      },
    );

    test('still prefers .png over .webp when both exist', () async {
      final png = await writeBox2d('Adventure Island II (USA, Europe).png');
      await writeBox2d('Adventure Island II (USA, Europe).webp');

      expect(game.getImagePath('gb', 'box2d', provider), png.path);
    });
  });

  group('looksLikeImage', () {
    test('accepts the formats RomM serves', () {
      expect(
        RommService.looksLikeImage(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00]),
        ),
        isTrue,
        reason: 'JPEG',
      );
      expect(
        RommService.looksLikeImage(
          Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]),
        ),
        isTrue,
        reason: 'PNG',
      );
      expect(
        RommService.looksLikeImage(
          Uint8List.fromList([
            0x52, 0x49, 0x46, 0x46, // RIFF
            0x00, 0x00, 0x00, 0x00, // size
            0x57, 0x45, 0x42, 0x50, // WEBP
          ]),
        ),
        isTrue,
        reason: 'WEBP',
      );
    });

    test('rejects the SPA shell RomM answers with for a missing resource', () {
      // A resource path RomM has no file for returns 200 + HTML, which written
      // out would look like downloaded art and render as nothing.
      final html = Uint8List.fromList('<!doctype html><html>'.codeUnits);
      expect(RommService.looksLikeImage(html), isFalse);
    });

    test('rejects empty and truncated bodies', () {
      expect(RommService.looksLikeImage(Uint8List(0)), isFalse);
      expect(
        RommService.looksLikeImage(Uint8List.fromList([0xFF, 0xD8])),
        isFalse,
      );
    });
  });
}
