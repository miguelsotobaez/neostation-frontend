import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/constants/system_folder_names.dart';
import 'package:neostation/data/datasources/sqlite_migrations.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/services/collections/collections_service.dart';
import 'package:neostation/services/game_service.dart';

import 'database_test_helper.dart';

/// Guards the contract that makes the per-collection games view behave like any
/// other system's: a collection reaches [SystemGamesList] as a synthesized
/// [SystemModel] whose `folderName` is `collection:<uuid>`, and every aggregate
/// branch in that view keys off that name (directly, or through
/// [SystemModel.primaryFolderName]).
///
/// Favourites is the reference implementation: whatever the favourites view
/// resolves, the collection view must resolve the same way.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const collectionId = '11111111-2222-4333-8444-555555555555';
  const collectionFolder = '${SystemFolderNames.collectionPrefix}$collectionId';

  /// The model the collections browser hands to the games list. The decorative
  /// `iconImage` is the part that matters: [SystemModel.primaryFolderName]
  /// derives its result from that path for ordinary systems.
  SystemModel collectionSystem() => SystemModel(
    id: collectionFolder,
    folderName: collectionFolder,
    realName: 'Co-op night',
    iconImage: '/images/icons/folder-bulk.png',
    color: '#7C4DFF',
    detected: true,
  );

  group('SystemModel.primaryFolderName for aggregate views', () {
    test('a collection keeps its own folder name, not the icon stem', () {
      // Without the aggregate short-circuit this derives 'folder' from
      // 'folder-bulk.png', and every isAggregate(primaryFolderName) check
      // downstream silently takes the single-system path.
      expect(collectionSystem().primaryFolderName, collectionFolder);
      expect(
        SystemFolderNames.isAggregate(collectionSystem().primaryFolderName),
        isTrue,
      );
    });

    test('favourites keeps its folder name even with a decorative icon', () {
      final favorites = SystemModel(
        id: SystemFolderNames.favorites,
        folderName: SystemFolderNames.favorites,
        realName: 'Favorites',
        iconImage: '/images/icons/heart-bulk.png',
        color: '#ff006a',
      );

      expect(favorites.primaryFolderName, SystemFolderNames.favorites);
    });

    test('all / all-background are unchanged', () {
      expect(
        SystemModel(
          id: 'all',
          folderName: 'all',
          realName: 'All',
          iconImage: '/images/icons/grid-bulk.png',
          color: '#9575cd',
        ).primaryFolderName,
        'all',
      );
      expect(
        SystemModel(
          id: 'all',
          folderName: 'all-background',
          realName: 'All',
          iconImage: '/images/icons/grid-bulk.png',
          color: '#9575cd',
        ).primaryFolderName,
        'all-background',
      );
    });

    test('a hardware system still derives its folder from the icon', () {
      final ps1 = SystemModel(
        id: 'ps1',
        folderName: 'psx',
        realName: 'PlayStation',
        iconImage: '/images/icons/ps1-icon.png',
        color: '#000000',
      );

      expect(ps1.primaryFolderName, 'ps1');
    });
  });

  group('SystemFolderNames.isAggregate', () {
    test('covers every view whose games span several systems', () {
      expect(SystemFolderNames.isAggregate('all'), isTrue);
      expect(SystemFolderNames.isAggregate('favorites'), isTrue);
      expect(SystemFolderNames.isAggregate('collections'), isTrue);
      expect(SystemFolderNames.isAggregate(collectionFolder), isTrue);

      expect(SystemFolderNames.isAggregate('nes'), isFalse);
      expect(SystemFolderNames.isAggregate('music'), isFalse);
      expect(SystemFolderNames.isAggregate('android'), isFalse);
      expect(SystemFolderNames.isAggregate(null), isFalse);
    });
  });

  group('GameService.loadGamesForSystem (collection)', () {
    final helper = DatabaseTestHelper();

    setUp(() async {
      final db = await helper.setUp();
      await SqliteMigrations.migrateToVersion(db.rawDb, 139);

      await db.execute(
        "INSERT INTO app_systems (id, real_name, folder_name, short_name) "
        "VALUES ('sys-nes', 'Nintendo Entertainment System', 'nes', 'NES')",
      );
      await db.execute(
        "INSERT INTO app_systems (id, real_name, folder_name, short_name) "
        "VALUES ('sys-snes', 'Super Nintendo', 'snes', 'SNES')",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, is_favorite) "
        "VALUES ('Contra.zip', '/roms/nes/Contra.zip', 'sys-nes', 0)",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, is_favorite) "
        "VALUES ('Mario.zip', '/roms/snes/Mario.zip', 'sys-snes', 1)",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, is_hidden) "
        "VALUES ('Hidden.zip', '/roms/nes/Hidden.zip', 'sys-nes', 1)",
      );
    });

    tearDown(() async {
      await helper.tearDown();
    });

    GameModel gameAt(String romPath) => GameModel(
      romname: romPath.split('/').last,
      realname: romPath.split('/').last,
      name: romPath.split('/').last,
      year: '',
      developer: '',
      publisher: '',
      genre: '',
      players: '',
      rating: 0.0,
      romPath: romPath,
    );

    test(
      'a collection: system model is dispatched to the collection loader',
      () async {
        final collection = await CollectionsService.createCollection('Co-op');
        await CollectionsService.addGame(
          collection.id,
          gameAt('/roms/nes/Contra.zip'),
        );
        await CollectionsService.addGame(
          collection.id,
          gameAt('/roms/snes/Mario.zip'),
        );

        final system = SystemModel(
          id: '${SystemFolderNames.collectionPrefix}${collection.id}',
          folderName: '${SystemFolderNames.collectionPrefix}${collection.id}',
          realName: collection.name,
          iconImage: '/images/icons/folder-bulk.png',
          color: '#7C4DFF',
          detected: true,
        );

        final games = await GameService.loadGamesForSystem(system);

        expect(games.map((g) => g.romname), ['Mario.zip', 'Contra.zip']);
      },
    );

    test('every game carries its own system identity', () async {
      final collection = await CollectionsService.createCollection('Co-op');
      await CollectionsService.addGame(
        collection.id,
        gameAt('/roms/nes/Contra.zip'),
      );

      final games = await GameService.loadGamesForSystem(
        SystemModel(
          id: '${SystemFolderNames.collectionPrefix}${collection.id}',
          folderName: '${SystemFolderNames.collectionPrefix}${collection.id}',
          realName: collection.name,
          iconImage: '/images/icons/folder-bulk.png',
          color: '#7C4DFF',
        ),
      );

      // Launch, artwork, scraping and the secondary display all resolve the
      // game's own system from these three fields; without them the collection
      // view would fall back to the collection itself, which has no
      // `app_systems` row.
      expect(games.single.systemId, 'sys-nes');
      expect(games.single.systemFolderName, 'nes');
      expect(games.single.systemRealName, 'Nintendo Entertainment System');
    });

    test('hidden ROMs are filtered, exactly as favourites does', () async {
      final collection = await CollectionsService.createCollection('Co-op');
      await CollectionsService.addGame(
        collection.id,
        gameAt('/roms/nes/Hidden.zip'),
      );
      await CollectionsService.addGame(
        collection.id,
        gameAt('/roms/nes/Contra.zip'),
      );

      final games = await GameService.loadGamesForSystem(
        SystemModel(
          id: '${SystemFolderNames.collectionPrefix}${collection.id}',
          folderName: '${SystemFolderNames.collectionPrefix}${collection.id}',
          realName: collection.name,
          iconImage: '/images/icons/folder-bulk.png',
          color: '#7C4DFF',
        ),
      );

      expect(games.map((g) => g.romname), ['Contra.zip']);
    });

    test('an empty collection loads as an empty list, not an error', () async {
      final collection = await CollectionsService.createCollection('Empty');

      final games = await GameService.loadGamesForSystem(
        SystemModel(
          id: '${SystemFolderNames.collectionPrefix}${collection.id}',
          folderName: '${SystemFolderNames.collectionPrefix}${collection.id}',
          realName: collection.name,
          iconImage: '/images/icons/folder-bulk.png',
          color: '#7C4DFF',
        ),
      );

      expect(games, isEmpty);
    });
  });
}
