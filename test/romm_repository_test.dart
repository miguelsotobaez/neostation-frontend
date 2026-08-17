import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/repositories/romm_repository.dart';
import 'package:neostation/repositories/romm_save_map_repository.dart';

import 'database_test_helper.dart';

void main() {
  final dbHelper = DatabaseTestHelper();
  late dynamic db;

  setUp(() async {
    db = await dbHelper.setUp();
    // RomM tables (migrations v91/v92) aren't part of the minimal schema.
    await db.execute('''
      CREATE TABLE user_romm_config (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        server_url TEXT,
        username TEXT,
        password TEXT,
        api_key TEXT,
        access_token TEXT,
        refresh_token TEXT,
        token_expires INTEGER,
        last_verified TEXT,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP
      )
    ''');
    await db.execute('''
      CREATE TABLE app_romm_rom_map (
        romname TEXT NOT NULL,
        system_folder TEXT NOT NULL,
        romm_rom_id INTEGER NOT NULL,
        romm_fs_name TEXT,
        updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
        PRIMARY KEY (romname, system_folder)
      )
    ''');
  });

  tearDown(() async {
    await dbHelper.tearDown();
  });

  group('RommRepository', () {
    test('getConfig returns null when nothing stored', () async {
      expect(await RommRepository.getConfig(), isNull);
    });

    test('saveConfig persists credentials and getConfig round-trips', () async {
      final ok = await RommRepository.saveConfig(
        serverUrl: 'https://romm.local',
        username: 'testuser',
        password: 's3cret',
      );
      expect(ok, isTrue);

      final config = await RommRepository.getConfig();
      expect(config, isNotNull);
      expect(config!['server_url'], 'https://romm.local');
      expect(config['username'], 'testuser');
      expect(config['password'], 's3cret');
      // Tokens are cleared on credential change.
      expect(config['access_token'], isNull);
      expect(config['refresh_token'], isNull);
      expect(config['token_expires'], isNull);
    });

    test('password is stored base64-encoded, not in plaintext', () async {
      await RommRepository.saveConfig(
        serverUrl: 'https://romm.local',
        username: 'testuser',
        password: 's3cret',
      );
      final row = (await db.query('user_romm_config')).first;
      expect(row['password'], base64Encode(utf8.encode('s3cret')));
      expect(row['password'], isNot('s3cret'));
    });

    test(
      'saveConfig replaces the singleton row rather than appending',
      () async {
        await RommRepository.saveConfig(
          serverUrl: 'https://a',
          username: 'u1',
          password: 'p1',
        );
        await RommRepository.saveConfig(
          serverUrl: 'https://b',
          username: 'u2',
          password: 'p2',
        );
        final rows = await db.query('user_romm_config');
        expect(rows, hasLength(1));
        expect((await RommRepository.getConfig())!['server_url'], 'https://b');
      },
    );

    test('saveConfig round-trips an API key instead of a password', () async {
      await RommRepository.saveConfig(
        serverUrl: 'https://romm.local',
        apiKey: 'rmm_deadbeef',
      );

      final config = await RommRepository.getConfig();
      expect(config!['api_key'], 'rmm_deadbeef');
      expect(config['username'], '');
      expect(config['password'], '');
    });

    test('the API key is stored base64-encoded, not in plaintext', () async {
      await RommRepository.saveConfig(
        serverUrl: 'https://romm.local',
        apiKey: 'rmm_deadbeef',
      );
      final row = (await db.query('user_romm_config')).first;
      expect(row['api_key'], base64Encode(utf8.encode('rmm_deadbeef')));
      expect(row['api_key'], isNot('rmm_deadbeef'));
    });

    test('switching to a password clears the stored API key', () async {
      await RommRepository.saveConfig(
        serverUrl: 'https://romm.local',
        apiKey: 'rmm_deadbeef',
      );
      await RommRepository.saveConfig(
        serverUrl: 'https://romm.local',
        username: 'testuser',
        password: 's3cret',
      );

      final config = await RommRepository.getConfig();
      expect(config!['api_key'], '');
      expect(config['password'], 's3cret');
    });

    test('switching to an API key clears the stored password', () async {
      await RommRepository.saveConfig(
        serverUrl: 'https://romm.local',
        username: 'testuser',
        password: 's3cret',
      );
      await RommRepository.saveConfig(
        serverUrl: 'https://romm.local',
        apiKey: 'rmm_deadbeef',
      );

      final config = await RommRepository.getConfig();
      expect(config!['password'], '');
      expect(config['api_key'], 'rmm_deadbeef');
    });

    test('getConfig reads an absent api_key as unset', () async {
      await db.execute(
        "INSERT INTO user_romm_config (id, server_url, username) "
        "VALUES (1, 'https://x', 'testuser')",
      );
      expect((await RommRepository.getConfig())!['api_key'], '');
    });

    test('getConfig returns null when server_url is empty', () async {
      await db.execute(
        "INSERT INTO user_romm_config (id, server_url, username) VALUES (1, '', 'testuser')",
      );
      expect(await RommRepository.getConfig(), isNull);
    });

    test('getConfig tolerates corrupt base64 password', () async {
      await db.execute(
        "INSERT INTO user_romm_config (id, server_url, password) VALUES (1, 'https://x', 'not~valid~base64')",
      );
      final config = await RommRepository.getConfig();
      expect(config, isNotNull);
      expect(config!['password'], '');
    });

    test('saveTokens caches JWTs retrievable via getConfig', () async {
      await RommRepository.saveConfig(
        serverUrl: 'https://romm.local',
        username: 'testuser',
        password: 's3cret',
      );
      final ok = await RommRepository.saveTokens(
        accessToken: 'access-123',
        refreshToken: 'refresh-456',
        tokenExpires: 1700000000000,
      );
      expect(ok, isTrue);

      final config = await RommRepository.getConfig();
      expect(config!['access_token'], 'access-123');
      expect(config['refresh_token'], 'refresh-456');
      expect(config['token_expires'], 1700000000000);
      expect(config['last_verified'], isNotNull);
    });

    test('saveTokens leaves refresh token untouched when omitted', () async {
      await RommRepository.saveConfig(
        serverUrl: 'https://romm.local',
        username: 'testuser',
        password: 's3cret',
      );
      await RommRepository.saveTokens(
        accessToken: 'a1',
        refreshToken: 'r1',
        tokenExpires: 1,
      );
      await RommRepository.saveTokens(accessToken: 'a2');

      final config = await RommRepository.getConfig();
      expect(config!['access_token'], 'a2');
      expect(config['refresh_token'], 'r1');
    });

    test('clearConfig removes all stored configuration', () async {
      await RommRepository.saveConfig(
        serverUrl: 'https://romm.local',
        username: 'testuser',
        password: 's3cret',
      );
      final ok = await RommRepository.clearConfig();
      expect(ok, isTrue);
      expect(await RommRepository.getConfig(), isNull);
      expect(await db.query('user_romm_config'), isEmpty);
    });
  });

  group('RommSaveMapRepository', () {
    test('getRommRomId returns null when unmapped', () async {
      expect(await RommSaveMapRepository.getRommRomId('a.sfc', 'snes'), isNull);
    });

    test('putMapping then getRommRomId round-trips', () async {
      await RommSaveMapRepository.putMapping(
        romname: 'Chrono Trigger.sfc',
        systemFolder: 'snes',
        rommRomId: 99,
        fsName: 'Chrono Trigger.sfc',
      );
      expect(
        await RommSaveMapRepository.getRommRomId('Chrono Trigger.sfc', 'snes'),
        99,
      );
    });

    // The mapping is written with the on-disk filename, but a GameModel's
    // `romname` has the extension stripped — so every lookup on the game-exit
    // path missed, and an unresolved id reads as "not a RomM game", silently
    // disabling save sync and playtime for a game that was downloaded here.
    test('a GameModel romname resolves against the stored filename', () async {
      await RommSaveMapRepository.putMapping(
        romname: 'Extra Mario Bros. [Hacks].zip',
        systemFolder: 'nes',
        rommRomId: 6320,
      );

      expect(
        await RommSaveMapRepository.getRommRomId(
          'Extra Mario Bros. [Hacks]',
          'nes',
        ),
        6320,
      );
    });

    test('stem matching stays scoped to the system folder', () async {
      await RommSaveMapRepository.putMapping(
        romname: 'game.bin',
        systemFolder: 'megadrive',
        rommRomId: 7,
      );

      expect(await RommSaveMapRepository.getRommRomId('game', 'snes'), isNull);
      expect(await RommSaveMapRepository.getRommRomId('game', 'megadrive'), 7);
    });

    test('a dotted title is not truncated into a false match', () async {
      await RommSaveMapRepository.putMapping(
        romname: 'Mr. Do.zip',
        systemFolder: 'nes',
        rommRomId: 11,
      );

      expect(await RommSaveMapRepository.getRommRomId('Mr. Do', 'nes'), 11);
      expect(await RommSaveMapRepository.getRommRomId('Mr', 'nes'), isNull);
    });

    test('mapping is scoped by both romname and system folder', () async {
      await RommSaveMapRepository.putMapping(
        romname: 'game.bin',
        systemFolder: 'snes',
        rommRomId: 1,
      );
      await RommSaveMapRepository.putMapping(
        romname: 'game.bin',
        systemFolder: 'megadrive',
        rommRomId: 2,
      );
      expect(await RommSaveMapRepository.getRommRomId('game.bin', 'snes'), 1);
      expect(
        await RommSaveMapRepository.getRommRomId('game.bin', 'megadrive'),
        2,
      );
    });

    test('putMapping replaces an existing mapping for the same key', () async {
      await RommSaveMapRepository.putMapping(
        romname: 'game.bin',
        systemFolder: 'snes',
        rommRomId: 1,
      );
      await RommSaveMapRepository.putMapping(
        romname: 'game.bin',
        systemFolder: 'snes',
        rommRomId: 2,
      );
      final rows = await db.query('app_romm_rom_map');
      expect(rows, hasLength(1));
      expect(await RommSaveMapRepository.getRommRomId('game.bin', 'snes'), 2);
    });

    test(
      'getIndexedNameForRomId returns null when the rom id is unmapped',
      () async {
        expect(
          await RommSaveMapRepository.getIndexedNameForRomId(42, 'psx'),
          isNull,
        );
      },
    );

    test('getIndexedNameForRomId recovers the recorded on-disk name by rom id '
        '(bundled multi-disc playlist detection)', () async {
      // A bundled-playlist multi-disc download records its arbitrary .m3u
      // basename as the indexed romname; detection reverse-looks it up by id.
      await RommSaveMapRepository.putMapping(
        romname: 'Final Fantasy VII (Disc set).m3u',
        systemFolder: 'psx',
        rommRomId: 7,
        fsName: 'Final Fantasy VII (Disc set).m3u',
      );
      expect(
        await RommSaveMapRepository.getIndexedNameForRomId(7, 'psx'),
        'Final Fantasy VII (Disc set).m3u',
      );
      // Scoped by system folder: a different folder must not match.
      expect(
        await RommSaveMapRepository.getIndexedNameForRomId(7, 'snes'),
        isNull,
      );
    });

    // Deleting a downloaded game locally has to unlink it, or RomM keeps
    // reporting it as already downloaded and refuses to fetch it again.
    test(
      'removeMapping unlinks a deleted game and reports its rom id',
      () async {
        await RommSaveMapRepository.putMapping(
          romname: 'Super Mario Bros.zip',
          systemFolder: 'nes',
          rommRomId: 6320,
        );

        expect(
          await RommSaveMapRepository.removeMapping(
            'Super Mario Bros.zip',
            'nes',
          ),
          6320,
        );
        expect(
          await RommSaveMapRepository.getRommRomId(
            'Super Mario Bros.zip',
            'nes',
          ),
          isNull,
        );
        expect(
          await RommSaveMapRepository.getIndexedNameForRomId(6320, 'nes'),
          isNull,
        );
      },
    );

    // A GameModel carries the extension already stripped, so the delete path
    // hands over a name the mapping was never written with.
    test('removeMapping unlinks via the extension-stripped romname', () async {
      await RommSaveMapRepository.putMapping(
        romname: 'Extra Mario Bros. [Hacks].zip',
        systemFolder: 'nes',
        rommRomId: 6320,
      );

      expect(
        await RommSaveMapRepository.removeMapping(
          'Extra Mario Bros. [Hacks]',
          'nes',
        ),
        6320,
      );
      expect(
        await RommSaveMapRepository.getRommRomId(
          'Extra Mario Bros. [Hacks]',
          'nes',
        ),
        isNull,
      );
    });

    test('removeMapping leaves other systems and games alone', () async {
      await RommSaveMapRepository.putMapping(
        romname: 'game.bin',
        systemFolder: 'megadrive',
        rommRomId: 7,
      );
      await RommSaveMapRepository.putMapping(
        romname: 'game.sfc',
        systemFolder: 'snes',
        rommRomId: 8,
      );

      expect(await RommSaveMapRepository.removeMapping('game', 'megadrive'), 7);
      expect(await RommSaveMapRepository.getRommRomId('game', 'snes'), 8);
    });

    test(
      'removeMapping returns null for a game that never came from RomM',
      () async {
        expect(
          await RommSaveMapRepository.removeMapping('Homebrew.nes', 'nes'),
          isNull,
        );
      },
    );
  });
}
