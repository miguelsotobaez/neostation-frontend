import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v153, which reopens the disc ROMs parked in containers
/// the reader has since learned to open.
///
/// A `.cso` — which is how most PSP libraries are stored — was parked as
/// `ra_hash_skipped = 'disc'` because nothing here could decompress one. The
/// match pass walks ROMs with no hash and steps over parked ones, so without
/// this the CISO reader would reach only newly added ROMs and a user whose
/// whole library is `.cso` would see no change at all.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE app_systems (
        id TEXT PRIMARY KEY,
        folder_name TEXT NOT NULL UNIQUE,
        real_name TEXT NOT NULL,
        ra_id INTEGER,
        multidisc INTEGER NOT NULL DEFAULT 0
      )
    ''');
    db.execute('''
      CREATE TABLE user_roms (
        filename TEXT,
        rom_path TEXT PRIMARY KEY,
        app_system_id TEXT,
        ra_hash TEXT,
        id_ra INTEGER,
        ra_match_source TEXT,
        ra_hash_skipped TEXT
      )
    ''');
    for (final system in const [
      ('psp', 'PlayStation Portable', 41),
      ('ps1', 'PlayStation', 12),
      ('pccd', 'PC Engine CD', 76),
      ('nes', 'NES', 7),
    ]) {
      db.execute(
        'INSERT INTO app_systems (id, folder_name, real_name, ra_id) '
        'VALUES (?, ?, ?, ?)',
        [system.$1, system.$1, system.$2, system.$3],
      );
    }
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV153() => SqliteMigrations.migrateToVersion(db, 153);

  void addRom(String filename, String system, String? skipped) {
    db.execute(
      'INSERT INTO user_roms (filename, rom_path, app_system_id, '
      'ra_hash_skipped) VALUES (?, ?, ?, ?)',
      [filename, '/roms/$system/$filename', system, skipped],
    );
  }

  String? skipReason(String filename) =>
      db.select('SELECT ra_hash_skipped FROM user_roms WHERE filename = ?', [
            filename,
          ]).single['ra_hash_skipped']
          as String?;

  group('migration v153', () {
    test('unparks the containers the reader can now open', () async {
      addRom('game.cso', 'psp', 'disc');
      addRom('game.ciso', 'psp', 'disc');
      addRom('game.ccd', 'ps1', 'disc');
      addRom('game.mds', 'ps1', 'disc');
      addRom('game.mdf', 'ps1', 'disc');

      await runV153();

      for (final filename in const [
        'game.cso',
        'game.ciso',
        'game.ccd',
        'game.mds',
        'game.mdf',
      ]) {
        expect(skipReason(filename), isNull, reason: filename);
      }
    });

    test('unparks a ROM whose extension is spelled in capitals', () async {
      addRom('GAME.CSO', 'psp', 'disc');

      await runV153();

      expect(skipReason('GAME.CSO'), isNull);
    });

    test('unparks an Android ROM behind a SAF content URI', () async {
      // Android ROM paths are document URIs whose separators are `%2F`-encoded,
      // and the extension is the only part of one this matches on.
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, "
        "ra_hash_skipped) VALUES ('saf.cso', "
        "'content://com.android.externalstorage.documents/document/"
        "primary%3Aemu%2Froms%2Fpsp%2Fsaf.cso', 'psp', 'disc')",
      );

      await runV153();

      expect(skipReason('saf.cso'), isNull);
    });

    test('leaves the containers still unreadable parked', () async {
      // Whole-file compression and the consoles with no hash here.
      addRom('game.gdi', 'ps1', 'disc');
      addRom('game.ecm', 'ps1', 'disc');

      await runV153();

      expect(skipReason('game.gdi'), 'disc');
      expect(skipReason('game.ecm'), 'disc');
    });

    test('leaves a stray disc image in a cartridge folder parked', () async {
      // Hashing the container is still the wrong answer there: the per-system
      // filter parked it for a different reason.
      addRom('stray.cso', 'nes', 'disc');

      await runV153();

      expect(skipReason('stray.cso'), 'disc');
    });

    test('leaves other skip reasons alone', () async {
      // A missing file or an oversized ROM is still a real problem; only the
      // disc marker on these containers became obsolete.
      addRom('gone.cso', 'psp', 'missing');
      addRom('huge.ccd', 'pccd', 'oversize');

      await runV153();

      expect(skipReason('gone.cso'), 'missing');
      expect(skipReason('huge.ccd'), 'oversize');
    });

    test('leaves a hash that was already found in place', () async {
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash, "
        "id_ra) VALUES ('matched.cso', '/roms/psp/matched.cso', 'psp', "
        "'abc123', 4242)",
      );

      await runV153();

      final row = db.select(
        'SELECT ra_hash, id_ra FROM user_roms WHERE filename = ?',
        ['matched.cso'],
      ).single;
      expect(row['ra_hash'], 'abc123');
      expect(row['id_ra'], 4242);
    });

    test('does nothing on a database with no skip column yet', () async {
      db.execute('DROP TABLE user_roms');
      db.execute('CREATE TABLE user_roms (rom_path TEXT PRIMARY KEY)');

      await expectLater(runV153(), completes);
    });
  });
}
