import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/repositories/collection_repository.dart';

import 'database_test_helper.dart';

void main() {
  final dbHelper = DatabaseTestHelper();
  late DatabaseAdapter db;

  setUp(() async {
    db = await dbHelper.setUp();
    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('snes', 'Super Nintendo', 'snes')",
    );
    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('nes', 'Nintendo Entertainment System', 'nes')",
    );
    await db.execute(
      "INSERT INTO user_roms (filename, rom_path, app_system_id, title_name) VALUES ('mario_world.smc', '/roms/snes/mario_world.smc', 'snes', 'Super Mario World')",
    );
    await db.execute(
      "INSERT INTO user_roms (filename, rom_path, app_system_id, title_name) VALUES ('mario_bros3.nes', '/roms/nes/mario_bros3.nes', 'nes', 'Super Mario Bros 3')",
    );
  });

  tearDown(() async {
    await dbHelper.tearDown();
  });

  group('CollectionRepository', () {
    test('creates, retrieves, and updates collections', () async {
      final id = await CollectionRepository.createCollection(
        name: 'Mario Series',
        description: 'All Mario games across systems',
      );
      expect(id, greaterThan(0));

      final collection = await CollectionRepository.getCollection(id);
      expect(collection, isNotNull);
      expect(collection!.name, 'Mario Series');
      expect(collection.description, 'All Mario games across systems');
      expect(collection.romCount, 0);

      await CollectionRepository.updateCollection(
        id,
        name: 'Mario Franchise',
        description: 'Updated description',
      );

      final updated = await CollectionRepository.getCollection(id);
      expect(updated!.name, 'Mario Franchise');
      expect(updated.description, 'Updated description');
    });

    test('adds, retrieves, and removes games in a collection', () async {
      final id = await CollectionRepository.createCollection(
        name: 'Mario Favorites',
      );

      await CollectionRepository.addGamesToCollection(id, [
        '/roms/snes/mario_world.smc',
        '/roms/nes/mario_bros3.nes',
      ]);

      var games = await CollectionRepository.getGamesForCollection(id);
      expect(games.length, 2);

      var collection = await CollectionRepository.getCollection(id);
      expect(collection!.romCount, 2);
      expect(collection.coverRomPaths.length, 2);

      expect(
        await CollectionRepository.isGameInCollection(
          id,
          '/roms/snes/mario_world.smc',
        ),
        isTrue,
      );
      expect(
        await CollectionRepository.isGameInCollection(
          id,
          '/roms/other/game.smc',
        ),
        isFalse,
      );

      final colIds = await CollectionRepository.getCollectionIdsForGame(
        '/roms/snes/mario_world.smc',
      );
      expect(colIds, contains(id));

      await CollectionRepository.removeGamesFromCollection(id, [
        '/roms/nes/mario_bros3.nes',
      ]);

      games = await CollectionRepository.getGamesForCollection(id);
      expect(games.length, 1);
      expect(games.first.romPath, '/roms/snes/mario_world.smc');
    });

    test('setGamesForCollection replaces full game list', () async {
      final id = await CollectionRepository.createCollection(
        name: 'Retro Hits',
      );

      await CollectionRepository.addGamesToCollection(id, [
        '/roms/nes/mario_bros3.nes',
      ]);
      expect((await CollectionRepository.getGamesForCollection(id)).length, 1);

      await CollectionRepository.setGamesForCollection(id, [
        '/roms/snes/mario_world.smc',
      ]);

      final games = await CollectionRepository.getGamesForCollection(id);
      expect(games.length, 1);
      expect(games.first.romPath, '/roms/snes/mario_world.smc');
    });

    test('deleteCollection removes collection and associated mappings', () async {
      final id = await CollectionRepository.createCollection(name: 'To Delete');
      await CollectionRepository.addGamesToCollection(id, [
        '/roms/snes/mario_world.smc',
      ]);

      await CollectionRepository.deleteCollection(id);

      final collection = await CollectionRepository.getCollection(id);
      expect(collection, isNull);

      final games = await CollectionRepository.getGamesForCollection(id);
      expect(games, isEmpty);

      final count = await db.rawQuery(
        "SELECT COUNT(*) as c FROM user_roms WHERE rom_path = '/roms/snes/mario_world.smc'",
      );
      expect(count.first['c'], 1);
    });
  });
}
