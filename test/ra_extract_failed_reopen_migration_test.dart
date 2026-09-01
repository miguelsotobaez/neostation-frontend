import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v154, which reopens the ROMs parked because their
/// archive could not be extracted.
///
/// A `.zip`/`.7z` whose SAF path was long enough could not be extracted at all:
/// the temp directory was named with the whole `%2F`-encoded document id and
/// overran the filesystem's 255-byte limit on one component. Those ROMs were
/// parked `ra_hash_skipped = 'extract_failed'`, and the match pass steps over
/// parked ROMs — so without this the extraction fix reaches newly added ROMs
/// only, and a library that already hit the bug never recovers.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE user_roms (
        filename TEXT,
        rom_path TEXT PRIMARY KEY,
        app_system_id TEXT,
        ra_hash TEXT,
        id_ra INTEGER,
        ra_hash_skipped TEXT
      )
    ''');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV154() => SqliteMigrations.migrateToVersion(db, 154);

  void addRom(String filename, String? skipped, {String? romPath}) {
    db.execute(
      'INSERT INTO user_roms (filename, rom_path, app_system_id, '
      'ra_hash_skipped) VALUES (?, ?, ?, ?)',
      [filename, romPath ?? '/roms/gba/$filename', 'gba', skipped],
    );
  }

  String? skipReason(String filename) =>
      db.select('SELECT ra_hash_skipped FROM user_roms WHERE filename = ?', [
            filename,
          ]).single['ra_hash_skipped']
          as String?;

  group('migration v154', () {
    test('unparks a ROM parked as extract_failed', () async {
      addRom('game.zip', 'extract_failed');
      addRom('other.7z', 'extract_failed');

      await runV154();

      expect(skipReason('game.zip'), isNull);
      expect(skipReason('other.7z'), isNull);
    });

    test('unparks the long SAF path that caused the bug', () async {
      // The shape that overran the name limit: a deep folder and a translation
      // patch name, every separator `%2F`-encoded.
      addRom(
        'summon-night.zip',
        'extract_failed',
        romPath:
            'content://com.android.externalstorage.documents/document/'
            'primary%3Aemu%2Froms%2Fgba%2FTranslations%20(GameBoy%20Advance)'
            '%2FSummon%20Night%20-%20Swordcraft%20Story%203%20%5BT-En%5D.zip',
      );

      await runV154();

      expect(skipReason('summon-night.zip'), isNull);
    });

    test('leaves other skip reasons alone', () async {
      // 'error' is the pass's general bucket: a ROM under it failed for some
      // other reason and this fix says nothing about it.
      addRom('broken.zip', 'error');
      addRom('gone.zip', 'missing');
      addRom('huge.zip', 'oversize');
      addRom('disc.cue', 'disc');

      await runV154();

      expect(skipReason('broken.zip'), 'error');
      expect(skipReason('gone.zip'), 'missing');
      expect(skipReason('huge.zip'), 'oversize');
      expect(skipReason('disc.cue'), 'disc');
    });

    test('leaves a hash that was already found in place', () async {
      db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash, "
        "id_ra) VALUES ('matched.zip', '/roms/gba/matched.zip', 'gba', "
        "'abc123', 4242)",
      );

      await runV154();

      final row = db.select(
        'SELECT ra_hash, id_ra FROM user_roms WHERE filename = ?',
        ['matched.zip'],
      ).single;
      expect(row['ra_hash'], 'abc123');
      expect(row['id_ra'], 4242);
    });

    test('is idempotent — running it twice changes nothing further', () async {
      addRom('game.zip', 'extract_failed');
      addRom('broken.zip', 'error');

      await runV154();
      await runV154();

      expect(skipReason('game.zip'), isNull);
      expect(skipReason('broken.zip'), 'error');
    });

    test('does nothing on a database with no skip column yet', () async {
      db.execute('DROP TABLE user_roms');
      db.execute('CREATE TABLE user_roms (rom_path TEXT PRIMARY KEY)');

      await expectLater(runV154(), completes);
    });
  });
}
