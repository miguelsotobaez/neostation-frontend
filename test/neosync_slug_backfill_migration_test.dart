import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';

/// Tests for migration v115, which adds `neosync_slug` to [app_emulators] and
/// backfills it with the same Dart derivation the runtime uses
/// (`CloudPathBuilder.slugFromEmulatorUniqueId`), so the stored slug always
/// matches the one `_resolveEmulatorSlugForGame` computes at sync time.
void main() {
  late Database db;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE app_os (
        id INTEGER PRIMARY KEY,
        name TEXT
      )
    ''');
    db.execute('''
      CREATE TABLE app_systems (
        id TEXT PRIMARY KEY,
        folder_name TEXT
      )
    ''');
    // Mirrors the real app_emulators schema: composite PK over
    // (os_id, unique_identifier), no `id` column.
    db.execute('''
      CREATE TABLE app_emulators (
        unique_identifier TEXT NOT NULL,
        os_id INTEGER NOT NULL,
        system_id TEXT NOT NULL,
        name TEXT NOT NULL,
        is_standalone INTEGER NOT NULL DEFAULT 0,
        core_filename TEXT,
        is_default INTEGER NOT NULL DEFAULT 0,
        is_default_core INTEGER NOT NULL DEFAULT 0,
        is_default_standalone INTEGER NOT NULL DEFAULT 0,
        is_ra_compatible INTEGER NOT NULL DEFAULT 0,
        android_package_name TEXT,
        android_activity_name TEXT,
        neosync_slug TEXT,
        PRIMARY KEY (os_id, unique_identifier),
        FOREIGN KEY (os_id) REFERENCES app_os(id) ON DELETE CASCADE,
        FOREIGN KEY (system_id) REFERENCES app_systems(id) ON DELETE CASCADE
      )
    ''');
  });

  tearDown(() {
    db.close();
  });

  Future<void> runV115() => SqliteMigrations.migrateToVersion(db, 115);

  Future<Map<String, String>> slugsByUniqueId() async {
    final rows = db.select(
      'SELECT unique_identifier, neosync_slug FROM app_emulators',
    );
    return {
      for (final r in rows)
        r['unique_identifier'].toString(): r['neosync_slug']?.toString() ?? '',
    };
  }

  group('migration v115 slug backfill', () {
    test('derives retroarch.<core> for a ra64 core id', () async {
      db.execute(
        "INSERT INTO app_emulators (os_id, system_id, name, unique_identifier) "
        "VALUES (1, 'snes', 'RetroArch64 Snes9x', 'snes.ra64.snes9x')",
      );

      await runV115();

      final slugs = await slugsByUniqueId();
      expect(slugs['snes.ra64.snes9x'], 'retroarch.snes9x');
    });

    test('derives retroarch.<core> for a ra and ra32 core id', () async {
      db.execute(
        "INSERT INTO app_emulators (os_id, system_id, name, unique_identifier) VALUES "
        "(1, 'ps1', 'PCSX ReARMed', 'ps1.ra.pcsx_rearmed'), "
        "(1, 'gb', 'mGBA', 'gb.ra32.mgba')",
      );

      await runV115();

      final slugs = await slugsByUniqueId();
      expect(slugs['ps1.ra.pcsx_rearmed'], 'retroarch.pcsx-rearmed');
      expect(slugs['gb.ra32.mgba'], 'retroarch.mgba');
    });

    test('derives the standalone slug for a non-RetroArch id', () async {
      db.execute(
        "INSERT INTO app_emulators (os_id, system_id, name, unique_identifier) VALUES "
        "(1, 'ps2', 'AetherSX2', 'ps2.come.nanodata.armsx2')",
      );

      await runV115();

      final slugs = await slugsByUniqueId();
      expect(slugs['ps2.come.nanodata.armsx2'], 'armsx2');
    });

    test('strips the binary extension from a desktop core filename', () async {
      db.execute(
        "INSERT INTO app_emulators (os_id, system_id, name, unique_identifier) VALUES "
        "(1, 'ps2', 'PCSX2', 'ps2.ra64.pcsx2')",
      );

      await runV115();

      final slugs = await slugsByUniqueId();
      expect(slugs['ps2.ra64.pcsx2'], 'retroarch.pcsx2');
    });

    test('leaves an already-set slug untouched', () async {
      db.execute(
        "INSERT INTO app_emulators (os_id, system_id, name, unique_identifier, neosync_slug) "
        "VALUES (1, 'snes', 'RetroArch64 Snes9x', 'snes.ra64.snes9x', 'custom')",
      );

      await runV115();

      final slugs = await slugsByUniqueId();
      expect(slugs['snes.ra64.snes9x'], 'custom');
    });
  });
}
