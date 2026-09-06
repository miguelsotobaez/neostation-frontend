import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/constants/system_folder_names.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/services/game_service.dart';
import 'package:neostation/utils/effective_system.dart';

import 'database_test_helper.dart';

/// Two defects that only show up in an aggregate view ('all', 'favorites',
/// `collection:<uuid>`), where the list's own system is a synthesized
/// placeholder rather than real hardware:
///
///  * anything resolving against the *list's* system instead of the selected
///    *game's* system gets a placeholder — for a collection, an id with no
///    `app_systems` row at all. That is what left the game settings dialog's
///    Emulator tab empty in every aggregate view;
///  * a game that stops belonging to the view has to leave the list, which
///    means the list must be reloaded — the favourite toggle only updates the
///    flag on the row already loaded.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const collectionId = '11111111-2222-4333-8444-555555555555';
  const collectionFolder = '${SystemFolderNames.collectionPrefix}$collectionId';

  SystemModel nes() => SystemModel(
    id: 'sys-nes',
    folderName: 'nes',
    realName: 'Nintendo Entertainment System',
    iconImage: '/images/systems/nes-icon.png',
    color: '#e60012',
    folders: const ['nes', 'famicom'],
    screenscraperId: 3,
    raId: '7',
  );

  SystemModel snes() => SystemModel(
    id: 'sys-snes',
    folderName: 'snes',
    realName: 'Super Nintendo',
    iconImage: '/images/systems/snes-icon.png',
    color: '#5b4b8a',
  );

  /// The placeholders the aggregate views hand to the games list. Favourites
  /// and 'all' at least have an `app_systems`-shaped id; a collection's is
  /// `collection:<uuid>`, which no row anywhere carries.
  SystemModel favouritesPlaceholder() => SystemModel(
    id: SystemFolderNames.favorites,
    folderName: SystemFolderNames.favorites,
    realName: 'Favorites',
    iconImage: '/images/icons/heart-bulk.png',
    color: '#ff006a',
  );

  SystemModel allPlaceholder() => SystemModel(
    id: SystemFolderNames.all,
    folderName: SystemFolderNames.all,
    realName: 'All Games',
    iconImage: '/images/icons/grid-bulk.png',
    color: '#9575cd',
  );

  SystemModel collectionPlaceholder() => SystemModel(
    id: collectionFolder,
    folderName: collectionFolder,
    realName: 'Co-op night',
    iconImage: '/images/icons/folder-bulk.png',
    color: '#7C4DFF',
  );

  GameModel game({
    String romname = 'Contra.zip',
    String romPath = '/roms/nes/Contra.zip',
    String? systemId,
    String? systemFolderName,
  }) => GameModel(
    romname: romname,
    realname: romname,
    name: romname,
    year: '',
    developer: '',
    publisher: '',
    genre: '',
    players: '',
    rating: 0.0,
    romPath: romPath,
    systemId: systemId,
    systemFolderName: systemFolderName,
  );

  group('resolveEffectiveSystem', () {
    test('a single-system view always keeps its own system', () {
      // Even when the game claims a different system, a real system's view is
      // authoritative — nothing about the old path may change.
      final resolved = resolveEffectiveSystem(
        listSystem: snes(),
        game: game(systemId: 'sys-nes', systemFolderName: 'nes'),
        detectedSystems: [nes(), snes()],
      );

      expect(resolved.id, 'sys-snes');
    });

    for (final placeholder in <(String, SystemModel Function())>[
      ('favorites', favouritesPlaceholder),
      ('all', allPlaceholder),
      ('collection', collectionPlaceholder),
    ]) {
      test('${placeholder.$1} resolves the game\'s own system by id', () {
        final resolved = resolveEffectiveSystem(
          listSystem: placeholder.$2(),
          game: game(systemId: 'sys-nes', systemFolderName: 'nes'),
          detectedSystems: [snes(), nes(), placeholder.$2()],
        );

        // Emulator enumeration keys off `system.id`, and the placeholder's id
        // owns no emulators (a collection's owns no row at all), so the
        // Emulator tab came up empty in all three views.
        expect(resolved.id, 'sys-nes');
        expect(resolved.screenscraperId, 3);
        expect(resolved.raId, '7');
      });
    }

    test('falls back to the folder name when the id is missing', () {
      // Rows loaded before the `system_id` alias landed arrive without an id.
      final resolved = resolveEffectiveSystem(
        listSystem: collectionPlaceholder(),
        game: game(systemFolderName: 'nes'),
        detectedSystems: [snes(), nes()],
      );

      expect(resolved.id, 'sys-nes');
    });

    test('falls back to an alias folder name', () {
      final resolved = resolveEffectiveSystem(
        listSystem: favouritesPlaceholder(),
        game: game(systemFolderName: 'famicom'),
        detectedSystems: [snes(), nes()],
      );

      expect(resolved.id, 'sys-nes');
    });

    test('never resolves to another aggregate placeholder', () {
      // The provider's detected systems include the virtual ones; resolving to
      // one of those would just reintroduce the bug.
      final resolved = resolveEffectiveSystem(
        listSystem: allPlaceholder(),
        game: game(
          systemId: SystemFolderNames.favorites,
          systemFolderName: SystemFolderNames.favorites,
        ),
        detectedSystems: [favouritesPlaceholder(), collectionPlaceholder()],
      );

      expect(resolved.folderName, SystemFolderNames.all);
    });

    test('unknown system falls back to the list system', () {
      final resolved = resolveEffectiveSystem(
        listSystem: collectionPlaceholder(),
        game: game(systemId: 'sys-gone', systemFolderName: 'gone'),
        detectedSystems: [nes(), snes()],
      );

      expect(resolved.folderName, collectionFolder);
    });

    test('a game with no system identity falls back to the list system', () {
      final resolved = resolveEffectiveSystem(
        listSystem: favouritesPlaceholder(),
        game: game(),
        detectedSystems: [nes(), snes()],
      );

      expect(resolved.folderName, SystemFolderNames.favorites);
    });
  });

  group('favourites view membership', () {
    final helper = DatabaseTestHelper();

    setUp(() async {
      final db = await helper.setUp();
      await SqliteMigrations.migrateToVersion(db.rawDb, 139);

      await db.execute(
        "INSERT INTO app_systems (id, real_name, folder_name, short_name) "
        "VALUES ('sys-nes', 'Nintendo Entertainment System', 'nes', 'NES')",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, is_favorite) "
        "VALUES ('Contra.zip', '/roms/nes/Contra.zip', 'sys-nes', 1)",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, is_favorite) "
        "VALUES ('Mario.zip', '/roms/snes/Mario.zip', 'sys-nes', 1)",
      );
    });

    tearDown(() async {
      await helper.tearDown();
    });

    test(
      'un-favouriting drops the game from the view, so it must reload',
      () async {
        final favourites = favouritesPlaceholder();

        var games = await GameService.loadGamesForSystem(favourites);
        expect(
          games.map((g) => g.romname),
          containsAll(['Contra.zip', 'Mario.zip']),
        );

        await GameService.toggleFavorite(
          games.firstWhere((g) => g.romname == 'Contra.zip'),
        );

        // The favourite toggle only flips the flag on the rows already held
        // in memory, so the un-favourited row stayed visible until something
        // rebuilt the list. Reloading is what actually drops it — the same
        // remedy the collection membership path already applies.
        games = await GameService.loadGamesForSystem(favourites);
        expect(games.map((g) => g.romname), ['Mario.zip']);
      },
    );

    test('favourites rows carry their own system identity', () async {
      // What the settings dialog resolves the emulator list against.
      final games = await GameService.loadGamesForSystem(
        favouritesPlaceholder(),
      );

      expect(games.first.systemId, 'sys-nes');
      expect(games.first.systemFolderName, 'nes');
    });
  });
}
