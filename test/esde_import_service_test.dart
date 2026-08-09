import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/repositories/scraper_repository.dart';
import 'package:neostation/services/esde_import_service.dart';
import 'package:xml/xml.dart';

import 'database_test_helper.dart';

void main() {
  group('EsdeImportService pure helpers', () {
    group('parseRating', () {
      test('scales ES-DE 0..1 rating up to the 0..20 scale', () {
        expect(EsdeImportService.parseRatingForTest('0.5'), 10.0);
        expect(EsdeImportService.parseRatingForTest('1'), 20.0);
        expect(EsdeImportService.parseRatingForTest('0'), 0.0);
      });

      test('clamps out-of-range values into 0..1 before scaling', () {
        expect(EsdeImportService.parseRatingForTest('2'), 20.0);
        expect(EsdeImportService.parseRatingForTest('-1'), 0.0);
      });

      test('returns null for null / blank / non-numeric input', () {
        expect(EsdeImportService.parseRatingForTest(null), isNull);
        expect(EsdeImportService.parseRatingForTest('   '), isNull);
        expect(EsdeImportService.parseRatingForTest('abc'), isNull);
      });
    });

    group('parseEsdeDateTime', () {
      test('parses a full ES-DE datetime', () {
        expect(
          EsdeImportService.parseEsdeDateTimeForTest('19950311T000000'),
          DateTime(1995, 3, 11),
        );
      });

      test('parses a date-only value (no time component)', () {
        expect(
          EsdeImportService.parseEsdeDateTimeForTest('20010921'),
          DateTime(2001, 9, 21),
        );
      });

      test('rejects placeholder / zero / malformed dates', () {
        expect(EsdeImportService.parseEsdeDateTimeForTest('00000000'), isNull);
        expect(EsdeImportService.parseEsdeDateTimeForTest('1995'), isNull);
        expect(EsdeImportService.parseEsdeDateTimeForTest(''), isNull);
        expect(EsdeImportService.parseEsdeDateTimeForTest(null), isNull);
      });
    });

    group('mediaSubdir', () {
      test('returns empty for a ROM directly in the system folder', () {
        expect(EsdeImportService.mediaSubdirForTest('./Sonic.md'), '');
        expect(EsdeImportService.mediaSubdirForTest('Sonic.md'), '');
      });

      test('returns the ROM subfolder relative to the system folder', () {
        expect(
          EsdeImportService.mediaSubdirForTest('./Hacks/Sonic.md'),
          'Hacks',
        );
        expect(EsdeImportService.mediaSubdirForTest('./A/B/Sonic.md'), 'A/B');
      });
    });

    group('selectGames', () {
      test('de-duplicates entries sharing a ROM filename', () {
        final doc = XmlDocument.parse('''
          <gameList>
            <game><path>./Sonic.md</path><name>Base</name></game>
            <game><path>./Hacks/Sonic.md</path><name>Hack</name></game>
          </gameList>
        ''');
        // esdeRoot doesn't exist, so _esdeMediaExists is false for both and the
        // first-seen entry is kept.
        final chosen = EsdeImportService.selectGamesForTest(
          doc,
          '/no/such/root',
          'megadrive',
        );
        expect(chosen.length, 1);
      });

      test('keeps distinct filenames', () {
        final doc = XmlDocument.parse('''
          <gameList>
            <game><path>./Sonic.md</path></game>
            <game><path>./Streets.md</path></game>
          </gameList>
        ''');
        final chosen = EsdeImportService.selectGamesForTest(
          doc,
          '/no/such/root',
          'megadrive',
        );
        expect(chosen.length, 2);
      });

      test('reads a gamelist with a second <alternativeEmulator> root', () {
        // ES-DE writes the per-system emulator override as a SECOND root
        // element ahead of <gameList>, which is invalid XML that only a
        // lenient parser accepts. Parsing as a fragment must still see the
        // games.
        final doc = XmlDocumentFragment.parse('''<?xml version="1.0"?>
<alternativeEmulator>
    <label>FinalBurn Neo</label>
</alternativeEmulator>
<gameList>
    <game><path>./fbneo/sonicwi2.zip</path><name>Aero Fighters 2</name></game>
    <game><path>./mame/dkong.zip</path><name>Donkey Kong</name></game>
</gameList>
''');
        final chosen = EsdeImportService.selectGamesForTest(
          doc,
          '/no/such/root',
          'arcade',
        );
        expect(chosen.length, 2);
      });
    });
  });

  group('EsdeImportService DB behavior', () {
    final dbHelper = DatabaseTestHelper();
    late dynamic db;

    setUp(() async {
      db = await dbHelper.setUp();
      await db.execute(
        "INSERT INTO app_systems (id, real_name, folder_name, screenscraper_id) VALUES ('snes', 'SNES', 'snes', 4)",
      );
    });

    tearDown(() async {
      await dbHelper.tearDown();
    });

    test(
      'reset deletes only ES-DE-created rows, not NeoStation partial scrapes',
      () async {
        // An ES-DE-created row (mergeEsdeMetadata sets esde_imported = 1).
        await ScraperRepository.mergeEsdeMetadata('snes', 'esde.smc', {
          'real_name': 'ES-DE Game',
        });
        // A NeoStation partial-scrape row: also is_fully_scraped = 0, but NOT
        // ES-DE-imported. reset() must leave this one untouched.
        await db.execute(
          "INSERT INTO user_screenscraper_metadata (app_system_id, filename, real_name, is_fully_scraped, esde_imported) VALUES ('snes', 'neo.smc', 'Neo Game', 0, 0)",
        );

        final deleted = await EsdeImportService.reset();
        expect(deleted, 1);

        final rows = await db.rawQuery(
          'SELECT filename FROM user_screenscraper_metadata ORDER BY filename',
        );
        expect(rows.length, 1);
        expect(rows.first['filename'], 'neo.smc');
      },
    );

    test(
      'import keys metadata on the scanned ROM filename, not the gamelist casing',
      () async {
        // Scanned ROM is lowercase; the gamelist lists it title-cased.
        await db.execute(
          "INSERT INTO user_roms (filename, rom_path, app_system_id) VALUES ('sonic.smc', '/roms/snes/sonic.smc', 'snes')",
        );

        final tempRoot = Directory.systemTemp.createTempSync('esde_test_');
        addTearDown(() => tempRoot.deleteSync(recursive: true));
        final systemDir = Directory('${tempRoot.path}/gamelists/snes')
          ..createSync(recursive: true);
        File('${systemDir.path}/gamelist.xml').writeAsStringSync('''
          <gameList>
            <game>
              <path>./Sonic.smc</path>
              <name>Sonic the Hedgehog</name>
              <rating>0.8</rating>
            </game>
          </gameList>
        ''');

        final result = await EsdeImportService.import(tempRoot.path);
        expect(result.gamesImported, 1);

        final rows = await db.rawQuery(
          'SELECT filename, real_name FROM user_screenscraper_metadata',
        );
        expect(rows.length, 1);
        // Keyed on the scanned casing so the case-sensitive display join
        // (user_roms.filename = metadata.filename) resolves.
        expect(rows.first['filename'], 'sonic.smc');
        expect(rows.first['real_name'], 'Sonic the Hedgehog');
      },
    );

    test(
      'import handles a gamelist with an <alternativeEmulator> root',
      () async {
        await db.execute(
          "INSERT INTO user_roms (filename, rom_path, app_system_id) VALUES ('sonic.smc', '/roms/snes/sonic.smc', 'snes')",
        );

        final tempRoot = Directory.systemTemp.createTempSync('esde_test_');
        addTearDown(() => tempRoot.deleteSync(recursive: true));
        final systemDir = Directory('${tempRoot.path}/gamelists/snes')
          ..createSync(recursive: true);
        // Exactly what ES-DE writes once the user picks a non-default emulator
        // for the system: two root elements in one file.
        File('${systemDir.path}/gamelist.xml').writeAsStringSync(
          '''<?xml version="1.0"?>
<alternativeEmulator>
    <label>Snes9x - Current</label>
</alternativeEmulator>
<gameList>
    <game>
        <path>./sonic.smc</path>
        <name>Sonic the Hedgehog</name>
        <altemulator>Snes9x - Current</altemulator>
    </game>
</gameList>
''',
        );

        final result = await EsdeImportService.import(tempRoot.path);
        expect(result.systemsSkipped, 0);
        expect(result.systemsMatched, 1);
        expect(result.gamesImported, 1);
      },
    );

    test('import does not skip games ES-DE marks hidden', () async {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id) VALUES ('sonic.smc', '/roms/snes/sonic.smc', 'snes')",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id) VALUES ('secret.smc', '/roms/snes/secret.smc', 'snes')",
      );

      final tempRoot = Directory.systemTemp.createTempSync('esde_test_');
      addTearDown(() => tempRoot.deleteSync(recursive: true));
      final systemDir = Directory('${tempRoot.path}/gamelists/snes')
        ..createSync(recursive: true);
      File('${systemDir.path}/gamelist.xml').writeAsStringSync('''
        <gameList>
          <game>
            <path>./sonic.smc</path>
            <name>Sonic the Hedgehog</name>
          </game>
          <game>
            <path>./secret.smc</path>
            <name>Hidden Game</name>
            <hidden>true</hidden>
            <favorite>true</favorite>
          </game>
        </gameList>
      ''');

      final result = await EsdeImportService.import(tempRoot.path);
      expect(result.gamesImported, 2);

      // Hiding a game in ES-DE must not withhold its metadata or stats here:
      // the user may well have forgotten they hid it.
      final rows = await db.rawQuery(
        'SELECT filename FROM user_screenscraper_metadata ORDER BY filename',
      );
      expect(rows.map((r) => r['filename']), ['secret.smc', 'sonic.smc']);
      final hiddenRom = await db.rawQuery(
        "SELECT is_favorite FROM user_roms WHERE filename = 'secret.smc'",
      );
      expect(hiddenRom.first['is_favorite'], 1);
    });

    test('import fills play_time only when NeoStation has none', () async {
      // sonic has never been played here; streets already has local playtime
      // that the import must not clobber.
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, play_time) VALUES ('sonic.smc', '/roms/snes/sonic.smc', 'snes', 0)",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, play_time) VALUES ('streets.smc', '/roms/snes/streets.smc', 'snes', 900)",
      );

      final tempRoot = Directory.systemTemp.createTempSync('esde_test_');
      addTearDown(() => tempRoot.deleteSync(recursive: true));
      final systemDir = Directory('${tempRoot.path}/gamelists/snes')
        ..createSync(recursive: true);
      File('${systemDir.path}/gamelist.xml').writeAsStringSync('''
        <gameList>
          <game>
            <path>./sonic.smc</path>
            <name>Sonic the Hedgehog</name>
            <playcount>3</playcount>
            <playtime>47</playtime>
          </game>
          <game>
            <path>./streets.smc</path>
            <name>Streets of Rage</name>
            <playtime>12</playtime>
          </game>
        </gameList>
      ''');

      await EsdeImportService.import(tempRoot.path);

      final rows = await db.rawQuery(
        'SELECT filename, play_time FROM user_roms ORDER BY filename',
      );
      expect(rows[0]['filename'], 'sonic.smc');
      expect(rows[0]['play_time'], 47);
      expect(rows[1]['filename'], 'streets.smc');
      expect(rows[1]['play_time'], 900);
    });

    test(
      'import links art for a system that has downloaded_media but no gamelist',
      () async {
        final tempRoot = Directory.systemTemp.createTempSync('esde_test_');
        addTearDown(() => tempRoot.deleteSync(recursive: true));

        // snes has a gamelist; nes has artwork only. ES-DE leaves systems in
        // this state whenever media outlives (or precedes) a gamelist.
        await db.execute(
          "INSERT INTO app_systems (id, real_name, folder_name, screenscraper_id) VALUES ('nes', 'NES', 'nes', 3)",
        );
        Directory(
          '${tempRoot.path}/gamelists/snes',
        ).createSync(recursive: true);
        File(
          '${tempRoot.path}/gamelists/snes/gamelist.xml',
        ).writeAsStringSync('<gameList></gameList>');
        Directory(
          '${tempRoot.path}/downloaded_media/nes/covers',
        ).createSync(recursive: true);

        await EsdeImportService.import(tempRoot.path);

        final rows = await db.rawQuery(
          "SELECT app_system_id, esde_media_dir FROM user_system_settings WHERE esde_media_dir IS NOT NULL ORDER BY app_system_id",
        );
        expect(rows.map((r) => r['app_system_id']).toList(), ['nes', 'snes']);
        expect(rows.first['esde_media_dir'], 'nes');
      },
    );
  });
}
