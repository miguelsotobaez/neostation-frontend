import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/user_data_location_service.dart';
import 'package:path/path.dart' as p;

/// Regression tests for the reported data-loss bug: pointing NeoStation's
/// user-data location at a pre-existing third-party folder (e.g. an ES-DE
/// directory full of `downloaded_media/` and `gamelists/`) and then migrating
/// must NOT destroy the foreign data. `migrateData` may only ever touch
/// NeoStation-owned entries.
void main() {
  group('UserDataLocationService.migrateData', () {
    late Directory tmp;
    late Directory esde; // source == NeoStation user-data pointed at ES-DE
    late Directory dest;

    late File scrapedArt; // foreign (ES-DE)
    late File gamelist; // foreign (ES-DE)
    late File esSystems; // foreign (ES-DE)
    late File db; // owned (NeoStation)
    late File neoArt; // owned (NeoStation, under media/)

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('neostation_migrate_test_');
      esde = Directory(p.join(tmp.path, 'ES-DE'))..createSync(recursive: true);
      dest = Directory(p.join(tmp.path, 'new-location'))
        ..createSync(recursive: true);

      // --- Foreign, precious data NeoStation did not create ---
      scrapedArt = File(
        p.join(esde.path, 'downloaded_media', 'snes', 'Chrono Trigger.png'),
      )..createSync(recursive: true);
      scrapedArt.writeAsStringSync('PRECIOUS ARTWORK BYTES');

      gamelist = File(p.join(esde.path, 'gamelists', 'snes', 'gamelist.xml'))
        ..createSync(recursive: true);
      gamelist.writeAsStringSync('<gameList>hours of scraping</gameList>');

      esSystems = File(p.join(esde.path, 'es_systems.xml'))
        ..createSync(recursive: true);
      esSystems.writeAsStringSync('<systemList/>');

      // --- NeoStation's own data cohabiting the same folder ---
      db = File(p.join(esde.path, 'data.sqlite'))..createSync(recursive: true);
      db.writeAsStringSync('db-bytes');

      neoArt = File(p.join(esde.path, 'media', 'snes', 'boxart', 'ct.png'))
        ..createSync(recursive: true);
      neoArt.writeAsStringSync('neostation-scraped');
    });

    tearDown(() async {
      if (await tmp.exists()) await tmp.delete(recursive: true);
    });

    test('preserves foreign ES-DE data in the source folder', () async {
      await UserDataLocationService.migrateData(
        sourceUserDataPath: esde.path,
        sourceMediaPath: p.join(esde.path, 'media'),
        destPath: dest.path,
      );

      // Foreign data must be untouched in the original folder.
      expect(scrapedArt.existsSync(), isTrue, reason: 'scraped art preserved');
      expect(gamelist.existsSync(), isTrue, reason: 'gamelist preserved');
      expect(
        esSystems.existsSync(),
        isTrue,
        reason: 'es_systems.xml preserved',
      );
      expect(
        scrapedArt.readAsStringSync(),
        'PRECIOUS ARTWORK BYTES',
        reason: 'foreign content is byte-for-byte intact',
      );

      // Foreign data must NOT be copied into the destination.
      expect(
        File(
          p.join(dest.path, 'downloaded_media', 'snes', 'Chrono Trigger.png'),
        ).existsSync(),
        isFalse,
        reason: 'foreign data is not migrated into dest',
      );
    });

    test('migrates NeoStation-owned data and removes it from source', () async {
      await UserDataLocationService.migrateData(
        sourceUserDataPath: esde.path,
        sourceMediaPath: p.join(esde.path, 'media'),
        destPath: dest.path,
      );

      // Owned files are now at the destination...
      expect(File(p.join(dest.path, 'data.sqlite')).existsSync(), isTrue);
      expect(
        File(
          p.join(dest.path, 'media', 'snes', 'boxart', 'ct.png'),
        ).existsSync(),
        isTrue,
      );
      // ...and removed from the source.
      expect(db.existsSync(), isFalse, reason: 'owned db moved out of source');
      expect(neoArt.existsSync(), isFalse, reason: 'owned art moved out');
    });

    test(
      'aborts without deleting anything if a copy fails (safety gate)',
      () async {
        // Force a copy failure: put a DIRECTORY where the owned dest file goes,
        // so File.copy() throws for data.sqlite.
        Directory(p.join(dest.path, 'data.sqlite')).createSync(recursive: true);

        await expectLater(
          UserDataLocationService.migrateData(
            sourceUserDataPath: esde.path,
            sourceMediaPath: p.join(esde.path, 'media'),
            destPath: dest.path,
          ),
          throwsA(isA<Exception>()),
        );

        // Nothing in the source was deleted — owned or foreign.
        expect(
          db.existsSync(),
          isTrue,
          reason: 'owned db not deleted on abort',
        );
        expect(neoArt.existsSync(), isTrue, reason: 'owned art not deleted');
        expect(scrapedArt.existsSync(), isTrue, reason: 'foreign art intact');
        expect(
          gamelist.existsSync(),
          isTrue,
          reason: 'foreign gamelist intact',
        );
      },
    );

    test(
      'exact reported repro: user-data pointed at ES-DE/downloaded_media',
      () async {
        // The reporting user set User Data Location to their scraped-media
        // folder itself (…/ES-DE/downloaded_media), which holds per-system art
        // subdirs directly under it. Migrating away from it must NOT wipe them.
        final downloadedMedia = Directory(
          p.join(tmp.path, 'ES-DE', 'downloaded_media'),
        )..createSync(recursive: true);

        // Foreign ES-DE art: <downloaded_media>/<system>/<type>/<file>.
        final snesCover = File(
          p.join(downloadedMedia.path, 'snes', 'covers', 'Chrono Trigger.jpg'),
        )..createSync(recursive: true);
        snesCover.writeAsStringSync('hours of scraping');
        final nesShot = File(
          p.join(downloadedMedia.path, 'nes', 'screenshots', 'Metroid.png'),
        )..createSync(recursive: true);
        nesShot.writeAsStringSync('more scraping');

        // NeoStation's own data written inside that same folder.
        File(
          p.join(downloadedMedia.path, 'data.sqlite'),
        ).writeAsStringSync('db');
        final neoBox = File(
          p.join(downloadedMedia.path, 'media', 'snes', 'boxart', 'ct.png'),
        )..createSync(recursive: true);
        neoBox.writeAsStringSync('neostation art');

        final newDest = Directory(p.join(tmp.path, 'relocated'))
          ..createSync(recursive: true);

        await UserDataLocationService.migrateData(
          sourceUserDataPath: downloadedMedia.path,
          sourceMediaPath: p.join(downloadedMedia.path, 'media'),
          destPath: newDest.path,
        );

        // ES-DE per-system art survives in place.
        expect(snesCover.existsSync(), isTrue, reason: 'snes cover preserved');
        expect(
          nesShot.existsSync(),
          isTrue,
          reason: 'nes screenshot preserved',
        );
        // NeoStation's own data was migrated out.
        expect(File(p.join(newDest.path, 'data.sqlite')).existsSync(), isTrue);
        expect(neoBox.existsSync(), isFalse, reason: 'owned art moved out');
      },
    );

    test('no-ops when source and dest are the same folder', () async {
      // Same physical folder, different path strings (trailing slash) — the
      // caller's string-equality guard would miss this.
      await UserDataLocationService.migrateData(
        sourceUserDataPath: esde.path,
        sourceMediaPath: p.join(esde.path, 'media'),
        destPath: '${esde.path}${Platform.pathSeparator}',
      );

      // Nothing was copied onto itself or deleted — owned AND foreign intact.
      expect(db.existsSync(), isTrue, reason: 'owned db intact');
      expect(db.readAsStringSync(), 'db-bytes', reason: 'db not truncated');
      expect(neoArt.existsSync(), isTrue, reason: 'owned art intact');
      expect(scrapedArt.existsSync(), isTrue, reason: 'foreign art intact');
    });

    test('throws on overlapping source/dest without deleting', () async {
      // dest nested inside source — copying a tree into itself is refused.
      final nested = p.join(esde.path, 'relocated');
      await expectLater(
        UserDataLocationService.migrateData(
          sourceUserDataPath: esde.path,
          sourceMediaPath: p.join(esde.path, 'media'),
          destPath: nested,
        ),
        throwsA(isA<Exception>()),
      );
      expect(db.existsSync(), isTrue, reason: 'nothing deleted on overlap');
      expect(scrapedArt.existsSync(), isTrue, reason: 'foreign art intact');
    });
  });
}
