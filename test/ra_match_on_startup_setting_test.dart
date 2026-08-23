import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_config_service.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/models/config_model.dart';

import 'database_test_helper.dart';

/// The startup match pass is opt-in, and the toggle is only a feature if the
/// read path picks it back up. A column that is written and never read has
/// happened more than once in this area, and in each case the write test
/// passed on its own.
void main() {
  final dbHelper = DatabaseTestHelper();

  setUp(() async => dbHelper.setUp());
  tearDown(() async => dbHelper.tearDown());

  group('match RetroAchievements on startup setting', () {
    test('a fresh config has the startup pass off', () {
      expect(const ConfigModel().raMatchOnStartup, isFalse);
    });

    test(
      'a database row written before the setting existed reads as off',
      () async {
        // No value ever written for the new column: its default stands in, and
        // an upgrade must not start hashing the library on its own.
        await SqliteService.saveUserConfig(appLanguage: 'en');

        final loaded = await SqliteConfigService.loadConfig();

        expect(loaded.raMatchOnStartup, isFalse);
      },
    );

    test('turning it on survives a save and reload', () async {
      await SqliteConfigService.saveConfig(
        const ConfigModel(raMatchOnStartup: true),
      );

      final loaded = await SqliteConfigService.loadConfig();

      expect(loaded.raMatchOnStartup, isTrue);
    });

    test('turning it back off survives a save and reload', () async {
      await SqliteConfigService.saveConfig(
        const ConfigModel(raMatchOnStartup: true),
      );
      await SqliteConfigService.saveConfig(
        const ConfigModel(raMatchOnStartup: false),
      );

      final loaded = await SqliteConfigService.loadConfig();

      expect(loaded.raMatchOnStartup, isFalse);
    });

    test('it does not disturb the neighbouring startup-scan toggle', () async {
      await SqliteConfigService.saveConfig(
        const ConfigModel(raMatchOnStartup: true, scanOnStartup: false),
      );

      final loaded = await SqliteConfigService.loadConfig();

      expect(loaded.raMatchOnStartup, isTrue);
      expect(loaded.scanOnStartup, isFalse);
    });

    test('the setting round-trips through JSON in both key forms', () {
      final asCamel = ConfigModel.fromJson(const {'raMatchOnStartup': true});
      final asSnake = ConfigModel.fromJson(const {'ra_match_on_startup': 1});

      expect(asCamel.raMatchOnStartup, isTrue);
      expect(asSnake.raMatchOnStartup, isTrue);
      expect(
        const ConfigModel(raMatchOnStartup: true).toJson()['raMatchOnStartup'],
        isTrue,
      );
      expect(ConfigModel.fromJson(const {}).raMatchOnStartup, isFalse);
    });

    test('copyWith carries the setting and leaves it alone by default', () {
      const on = ConfigModel(raMatchOnStartup: true);

      expect(on.copyWith().raMatchOnStartup, isTrue);
      expect(on.copyWith(raMatchOnStartup: false).raMatchOnStartup, isFalse);
    });
  });
}
