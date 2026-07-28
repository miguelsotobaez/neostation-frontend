import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/providers/file_provider.dart';

import 'database_test_helper.dart';

void main() {
  group('FileProvider.stripRomExtension', () {
    test('strips known common ROM extensions', () {
      expect(FileProvider.stripRomExtension('game.zip'), 'game');
      expect(FileProvider.stripRomExtension('Sonic.md'), 'Sonic');
      expect(FileProvider.stripRomExtension('Mega Man X4.chd'), 'Mega Man X4');
    });

    test('preserves version-like suffixes', () {
      expect(FileProvider.stripRomExtension('game.v1'), 'game.v1');
      expect(FileProvider.stripRomExtension('game.123'), 'game.123');
    });

    test('leaves names without an extension untouched', () {
      expect(FileProvider.stripRomExtension('noext'), 'noext');
    });

    test('strips against a system-specific extension whitelist', () {
      expect(FileProvider.stripRomExtension('game.zip', {'zip'}), 'game');
    });

    test('does not strip a long non-whitelisted suffix', () {
      // 'foobar' is 6 chars, not a common ROM ext, and not whitelisted.
      expect(
        FileProvider.stripRomExtension('game.foobar', {'zip'}),
        'game.foobar',
      );
    });
  });

  group('FileProvider.getEsdeMediaCandidates', () {
    final dbHelper = DatabaseTestHelper();
    late dynamic db;
    late FileProvider provider;

    setUp(() async {
      db = await dbHelper.setUp();
      await db.execute(
        "INSERT INTO app_systems (id, real_name, folder_name, screenscraper_id) VALUES ('snes', 'SNES', 'snes', 4)",
      );
      await db.execute(
        "INSERT INTO user_config (esde_folder_path) VALUES ('/esde')",
      );
      await db.execute(
        "INSERT INTO user_system_settings (app_system_id, esde_media_dir) VALUES ('snes', 'snes')",
      );
      provider = FileProvider();
      await provider.refreshEsde();
    });

    tearDown(() async {
      await dbHelper.tearDown();
    });

    test('covers every mapped ES-DE category and extension', () {
      final candidates = provider.getEsdeMediaCandidates(
        'snes',
        'box2d',
        'sonic.smc',
      );
      expect(candidates, [
        '/esde/downloaded_media/snes/covers/sonic.png',
        '/esde/downloaded_media/snes/covers/sonic.jpg',
        '/esde/downloaded_media/snes/3dboxes/sonic.png',
        '/esde/downloaded_media/snes/3dboxes/sonic.jpg',
      ]);
    });

    test(
      'falls back to the category root after the recorded subfolder',
      () async {
        await db.execute(
          "INSERT INTO user_screenscraper_metadata (app_system_id, filename, esde_media_subdir) VALUES ('snes', 'sonic.smc', 'Hacks')",
        );
        await provider.refreshEsde();

        final candidates = provider.getEsdeMediaCandidates(
          'snes',
          'wheels',
          'sonic.smc',
        );
        expect(candidates, [
          '/esde/downloaded_media/snes/marquees/Hacks/sonic.png',
          '/esde/downloaded_media/snes/marquees/Hacks/sonic.jpg',
          '/esde/downloaded_media/snes/marquees/sonic.png',
          '/esde/downloaded_media/snes/marquees/sonic.jpg',
        ]);
      },
    );

    test('returns nothing for a system with no recorded ES-DE media dir', () {
      expect(
        provider.getEsdeMediaCandidates('nes', 'box2d', 'mario.nes'),
        isEmpty,
      );
    });
  });
}
