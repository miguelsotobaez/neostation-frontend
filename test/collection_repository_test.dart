import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/repositories/collection_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'database_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final dbHelper = DatabaseTestHelper();
  late DatabaseAdapter db;

  setUp(() async {
    db = await dbHelper.setUp();
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('xyz.luan/gamepads'),
          (call) async => <dynamic>[],
        );

    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('snes', 'Super Nintendo', 'snes')",
    );
    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('nes', 'Nintendo Entertainment System', 'nes')",
    );
    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('ps1', 'Sony PlayStation', 'ps1')",
    );
    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name) VALUES ('n64', 'Nintendo 64', 'n64')",
    );
    await db.execute(
      "INSERT INTO user_roms (filename, rom_path, app_system_id, title_name) VALUES ('mario_world.smc', '/roms/snes/mario_world.smc', 'snes', 'Super Mario World')",
    );
    await db.execute(
      "INSERT INTO user_roms (filename, rom_path, app_system_id, title_name) VALUES ('mario_bros3.nes', '/roms/nes/mario_bros3.nes', 'nes', 'Super Mario Bros 3')",
    );
    await db.execute(
      "INSERT INTO user_roms (filename, rom_path, app_system_id, title_name) VALUES ('crash.chd', '/roms/ps1/crash.chd', 'ps1', 'Crash Bandicoot')",
    );
    await db.execute(
      "INSERT INTO user_roms (filename, rom_path, app_system_id, title_name) VALUES ('gt.chd', '/roms/ps1/gt.chd', 'ps1', 'Gran Turismo')",
    );
    await db.execute(
      "INSERT INTO user_roms (filename, rom_path, app_system_id, title_name) VALUES ('fzero.smc', '/roms/snes/fzero.smc', 'snes', 'F-Zero')",
    );
    await db.execute(
      "INSERT INTO user_roms (filename, rom_path, app_system_id, title_name) VALUES ('mariokart64.z64', '/roms/n64/mariokart64.z64', 'n64', 'Mario Kart 64')",
    );
    await db.execute(
      "INSERT INTO user_roms (filename, rom_path, app_system_id, title_name) VALUES ('game1.smc', '/roms/snes/game1.smc', 'snes', 'Game 1')",
    );
    await db.execute(
      "INSERT INTO user_roms (filename, rom_path, app_system_id, title_name) VALUES ('game2.smc', '/roms/snes/game2.smc', 'snes', 'Game 2')",
    );
    await db.execute(
      "INSERT INTO user_roms (filename, rom_path, app_system_id, title_name) VALUES ('zelda.smc', '/roms/snes/zelda.smc', 'snes', 'Zelda')",
    );
  });

  tearDown(() async {
    await dbHelper.tearDown();
  });

  group('CollectionRepository', () {
    test('creates, retrieves, and updates collections', () async {
      final id = await CollectionRepository.createCollection(
        name: 'Mario Series',
      );
      expect(id, greaterThan(0));

      final collection = await CollectionRepository.getCollection(id);
      expect(collection, isNotNull);
      expect(collection!.name, 'Mario Series');
      expect(collection.romCount, 0);

      await CollectionRepository.updateCollection(id, name: 'Mario Franchise');

      final updated = await CollectionRepository.getCollection(id);
      expect(updated!.name, 'Mario Franchise');
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

      final isInCollection = await CollectionRepository.isGameInCollection(
        id,
        '/roms/snes/mario_world.smc',
      );
      expect(isInCollection, isTrue);

      final isNotInCollection = await CollectionRepository.isGameInCollection(
        id,
        '/roms/ps1/crash.chd',
      );
      expect(isNotInCollection, isFalse);

      await CollectionRepository.removeGamesFromCollection(id, [
        '/roms/nes/mario_bros3.nes',
      ]);

      games = await CollectionRepository.getGamesForCollection(id);
      expect(games.length, 1);
      expect(games.first.romPath, '/roms/snes/mario_world.smc');
    });

    test('setGamesForCollection replaces full game membership', () async {
      final id = await CollectionRepository.createCollection(
        name: 'Racing Favorites',
      );

      await CollectionRepository.addGamesToCollection(id, [
        '/roms/ps1/gt.chd',
        '/roms/snes/fzero.smc',
      ]);

      await CollectionRepository.setGamesForCollection(id, [
        '/roms/n64/mariokart64.z64',
      ]);

      final games = await CollectionRepository.getGamesForCollection(id);
      expect(games.length, 1);
      expect(games.first.romPath, '/roms/n64/mariokart64.z64');
    });

    test('deleting collection cascades ROM associations', () async {
      final id = await CollectionRepository.createCollection(
        name: 'Temp Collection',
      );

      await CollectionRepository.addGamesToCollection(id, [
        '/roms/snes/game1.smc',
        '/roms/snes/game2.smc',
      ]);

      await CollectionRepository.deleteCollection(id);

      final collection = await CollectionRepository.getCollection(id);
      expect(collection, isNull);

      final games = await CollectionRepository.getGamesForCollection(id);
      expect(games, isEmpty);
    });

    test(
      'getCollectionIdsForGame returns all collections containing the game',
      () async {
        final col1 = await CollectionRepository.createCollection(name: 'Col 1');
        final col2 = await CollectionRepository.createCollection(name: 'Col 2');
        final col3 = await CollectionRepository.createCollection(name: 'Col 3');

        const romPath = '/roms/snes/zelda.smc';
        await CollectionRepository.addGamesToCollection(col1, [romPath]);
        await CollectionRepository.addGamesToCollection(col3, [romPath]);

        final ids = await CollectionRepository.getCollectionIdsForGame(romPath);
        expect(ids.toSet(), equals({col1, col3}));
        expect(ids.contains(col2), isFalse);
      },
    );
  });
}
