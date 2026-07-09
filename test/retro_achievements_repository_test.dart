import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/repositories/retro_achievements_repository.dart';

import 'database_test_helper.dart';

void main() {
  final dbHelper = DatabaseTestHelper();
  late dynamic db;

  setUp(() async {
    db = await dbHelper.setUp();
    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name, ra_id) VALUES ('nes', 'NES', 'nes', '7')",
    );
  });

  tearDown(() async {
    await dbHelper.tearDown();
  });

  group('RetroAchievementsRepository', () {
    test('getLocalRomStats returns zero when no ROMs', () async {
      final stats = await RetroAchievementsRepository.getLocalRomStats();
      expect(stats.totalRoms, 0);
      expect(stats.raCompatibleRoms, 0);
    });

    test('getLocalRomStats counts RA-compatible ROMs', () async {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash) VALUES ('a.nes', '/roms/nes/a.nes', 'nes', 'abc123')",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash) VALUES ('b.nes', '/roms/nes/b.nes', 'nes', '')",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, ra_hash) VALUES ('c.nes', '/roms/nes/c.nes', 'nes', NULL)",
      );

      final stats = await RetroAchievementsRepository.getLocalRomStats();
      expect(stats.totalRoms, 3);
      expect(stats.raCompatibleRoms, 1);
    });

    test('getRAUser returns null when not set', () async {
      final user = await RetroAchievementsRepository.getRAUser();
      expect(user, isNull);
    });

    test('saveRAUser persists username', () async {
      await RetroAchievementsRepository.saveRAUser('TestUser');
      final user = await RetroAchievementsRepository.getRAUser();
      expect(user, 'TestUser');
    });

    test('clearRAUser removes username', () async {
      await RetroAchievementsRepository.saveRAUser('TestUser');
      await RetroAchievementsRepository.clearRAUser();
      final user = await RetroAchievementsRepository.getRAUser();
      expect(user, isNull);
    });

    test('updateRomRaGameId persists game id', () async {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id) VALUES ('a.nes', '/roms/nes/a.nes', 'nes')",
      );

      await RetroAchievementsRepository.updateRomRaGameId(
        '/roms/nes/a.nes',
        1234,
      );

      final result = await db.rawQuery(
        "SELECT id_ra FROM user_roms WHERE rom_path = '/roms/nes/a.nes'",
      );
      expect(result.first['id_ra'], 1234);
    });

    test('findRAHashByConsoleName returns hash and gameId', () async {
      await db.execute(
        "INSERT INTO app_ra_game_list (hash, game_id, console_name, title) VALUES ('deadbeef', 99, 'Nintendo Entertainment System', 'Mario')",
      );

      final result = await RetroAchievementsRepository.findRAHashByConsoleName(
        'Nintendo',
        '%Mario%',
      );
      expect(result, isNotNull);
      expect(result!.hash, 'deadbeef');
      expect(result.gameId, 99);
    });

    test('updateRomRAData updates hash and id_ra', () async {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id) VALUES ('a.nes', '/roms/nes/a.nes', 'nes')",
      );

      await RetroAchievementsRepository.updateRomRAData(
        'a.nes',
        'nes',
        'hash123',
        42,
      );

      final result = await db.rawQuery(
        "SELECT ra_hash, id_ra FROM user_roms WHERE filename = 'a.nes' AND app_system_id = 'nes'",
      );
      expect(result.first['ra_hash'], 'hash123');
      expect(result.first['id_ra'], 42);
    });

    test('findGameIdByHash returns game_id by exact hash', () async {
      await db.execute(
        "INSERT INTO app_ra_game_list (hash, game_id) VALUES ('abc123', 1001)",
      );

      final gameId = await RetroAchievementsRepository.findGameIdByHash(
        'abc123',
      );
      expect(gameId, 1001);
    });

    test('findGameIdByFilename returns exact match first', () async {
      await db.execute(
        "INSERT INTO app_ra_game_list (hash, game_id, console_id, title) VALUES ('h1', 2001, '7', 'Super Mario Bros')",
      );

      final gameId = await RetroAchievementsRepository.findGameIdByFilename(
        'nes',
        'Super Mario Bros',
      );
      expect(gameId, 2001);
    });

    test('findGameIdByFilename falls back to LIKE match', () async {
      await db.execute(
        "INSERT INTO app_ra_game_list (hash, game_id, console_id, title) VALUES ('h1', 3001, '7', 'Legend of Zelda')",
      );

      final gameId = await RetroAchievementsRepository.findGameIdByFilename(
        'nes',
        'Zelda',
      );
      expect(gameId, 3001);
    });

    test('findGameIdByFilename returns null when no match', () async {
      final gameId = await RetroAchievementsRepository.findGameIdByFilename(
        'nes',
        'Missing',
      );
      expect(gameId, isNull);
    });

    test(
      'findBestLocalGameByRaGameId prefers most recently played match',
      () async {
        await db.execute(
          "INSERT INTO user_roms (filename, rom_path, app_system_id, id_ra, is_favorite, last_played) VALUES ('older.nes', '/roms/nes/older.nes', 'nes', 777, 0, '2024-01-01T00:00:00.000')",
        );
        await db.execute(
          "INSERT INTO user_roms (filename, rom_path, app_system_id, id_ra, is_favorite, last_played) VALUES ('newer.nes', '/roms/nes/newer.nes', 'nes', 777, 0, '2024-02-01T00:00:00.000')",
        );

        final result =
            await RetroAchievementsRepository.findBestLocalGameByRaGameId(777);

        expect(result, isNotNull);
        expect(result!.game.romPath, '/roms/nes/newer.nes');
      },
    );

    test('findBestLocalGameByRaGameId breaks ties by favorite then name', () async {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, id_ra, is_favorite, last_played, title_name) VALUES ('b.nes', '/roms/nes/b.nes', 'nes', 888, 0, NULL, 'Bravo')",
      );
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id, id_ra, is_favorite, last_played, title_name) VALUES ('a.nes', '/roms/nes/a.nes', 'nes', 888, 1, NULL, 'Alpha')",
      );

      final result =
          await RetroAchievementsRepository.findBestLocalGameByRaGameId(888);

      expect(result, isNotNull);
      expect(result!.game.romPath, '/roms/nes/a.nes');
      expect(result.game.systemFolderName, 'nes');
    });
  });
}
