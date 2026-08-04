import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_database_service.dart';
import 'package:neostation/models/system_model.dart';

import 'database_test_helper.dart';

/// EmuDeck ships alias directories as symlinks (roms/gamecube -> roms/gc), and
/// both names are registered folders of the same system, so an unguarded scan
/// finds every file twice and stores it under two rom_path spellings.
void main() {
  final dbHelper = DatabaseTestHelper();
  late dynamic db;

  const gcSystem = SystemModel(
    id: 'gc',
    realName: 'Nintendo GameCube',
    folderName: 'gc',
    iconImage: '',
    color: '#000000',
    recursiveScan: true,
  );

  setUp(() async {
    db = await dbHelper.setUp();
    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('gc', 'Nintendo GameCube', 'gc')",
    );
    await db.execute(
      "INSERT INTO app_system_extensions (system_id, extension) VALUES ('gc', 'rvz')",
    );
    for (final alias in ['GameCube', 'Nintendo GameCube', 'gc', 'ngc']) {
      await db.rawInsert(
        'INSERT INTO app_system_folders (system_id, folder_name) VALUES (?, ?)',
        ['gc', alias],
      );
    }
  });

  tearDown(() async {
    await dbHelper.tearDown();
  });

  /// Builds `<root>/gc` holding [filenames], plus a `<root>/gamecube` symlink
  /// pointing at it, mirroring an EmuDeck layout.
  Future<Directory> createAliasedRomTree(List<String> filenames) async {
    final root = await Directory.systemTemp.createTemp('neostation_symlink_');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    final real = Directory('${root.path}/gc')..createSync(recursive: true);
    for (final name in filenames) {
      File('${real.path}/$name').writeAsStringSync('rom');
    }
    Link('${root.path}/gamecube').createSync(real.path);
    return root;
  }

  Future<List<Map<String, Object?>>> romRows() async {
    return await db.rawQuery(
      "SELECT filename, rom_path, is_favorite, play_time, last_played, id_ra "
      "FROM user_roms WHERE app_system_id = 'gc' ORDER BY rom_path",
    );
  }

  group('ROM scan across symlinked alias folders', () {
    test('stores one row per physical file, at the real path', () async {
      final root = await createAliasedRomTree(['18 Wheeler.rvz']);

      await SqliteDatabaseService.scanSystemRoms(gcSystem, [root.path]);

      final rows = await romRows();
      expect(rows, hasLength(1));
      expect(rows.single['rom_path'], '${root.path}/gc/18 Wheeler.rvz');
    });

    test('still scans an alias that is a real directory of its own', () async {
      final root = await Directory.systemTemp.createTemp('neostation_symlink_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      Directory('${root.path}/gc').createSync(recursive: true);
      Directory('${root.path}/ngc').createSync(recursive: true);
      File('${root.path}/gc/A.rvz').writeAsStringSync('rom');
      File('${root.path}/ngc/B.rvz').writeAsStringSync('rom');

      await SqliteDatabaseService.scanSystemRoms(gcSystem, [root.path]);

      final rows = await romRows();
      expect(rows.map((r) => r['filename']), ['A.rvz', 'B.rvz']);
    });

    test(
      'keeps the real directory when the primary folder is the link',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'neostation_symlink_',
        );
        addTearDown(() async {
          if (await root.exists()) await root.delete(recursive: true);
        });

        // Reversed layout: the alias is the real directory, `gc` links to it.
        final real = Directory('${root.path}/gamecube')
          ..createSync(recursive: true);
        File('${real.path}/Wave Race.rvz').writeAsStringSync('rom');
        Link('${root.path}/gc').createSync(real.path);

        await SqliteDatabaseService.scanSystemRoms(gcSystem, [root.path]);

        final rows = await romRows();
        expect(rows, hasLength(1));
        expect(rows.single['rom_path'], '${real.path}/Wave Race.rvz');
      },
    );

    test('deduplicates files held in subdirectories', () async {
      final root = await Directory.systemTemp.createTemp('neostation_symlink_');
      addTearDown(() async {
        if (await root.exists()) await root.delete(recursive: true);
      });

      final sub = Directory('${root.path}/gc/Multi Disc')
        ..createSync(recursive: true);
      File('${sub.path}/Baten Kaitos.rvz').writeAsStringSync('rom');
      Link('${root.path}/gamecube').createSync('${root.path}/gc');

      await SqliteDatabaseService.scanSystemRoms(gcSystem, [root.path]);

      expect(await romRows(), hasLength(1));
    });
  });
}
