import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_config_service.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/models/config_model.dart';

import 'database_test_helper.dart';

/// The achievements badge is opt-in, and the setting is only a feature if the
/// read path picks it up again. A column that is written and never read has
/// happened twice in this area already (the manual match picker, and the
/// console filter), and in both cases the write test passed on its own.
void main() {
  final dbHelper = DatabaseTestHelper();

  setUp(() async => dbHelper.setUp());
  tearDown(() async => dbHelper.tearDown());

  group('show achievements badge setting', () {
    test('a fresh config has the badge off', () {
      expect(const ConfigModel().showAchievementsBadge, isFalse);
    });

    test(
      'a database row written before the setting existed reads as off',
      () async {
        // No badge column value ever written: the column default stands in.
        await SqliteService.saveUserConfig(appLanguage: 'en');

        final loaded = await SqliteConfigService.loadConfig();

        expect(loaded.showAchievementsBadge, isFalse);
      },
    );

    test('turning it on survives a save and reload', () async {
      await SqliteConfigService.saveConfig(
        const ConfigModel(showAchievementsBadge: true),
      );

      final loaded = await SqliteConfigService.loadConfig();

      expect(loaded.showAchievementsBadge, isTrue);
    });

    test('turning it back off survives a save and reload', () async {
      await SqliteConfigService.saveConfig(
        const ConfigModel(showAchievementsBadge: true),
      );
      await SqliteConfigService.saveConfig(
        const ConfigModel(showAchievementsBadge: false),
      );

      final loaded = await SqliteConfigService.loadConfig();

      expect(loaded.showAchievementsBadge, isFalse);
    });

    test('the setting round-trips through JSON in both key forms', () {
      final asCamel = ConfigModel.fromJson(const {
        'showAchievementsBadge': true,
      });
      final asColumn = ConfigModel.fromJson(const {
        'show_achievements_badge': 1,
      });
      final absent = ConfigModel.fromJson(const {});

      expect(asCamel.showAchievementsBadge, isTrue);
      expect(asColumn.showAchievementsBadge, isTrue);
      expect(absent.showAchievementsBadge, isFalse);
      expect(
        ConfigModel.fromJson(
          const ConfigModel(showAchievementsBadge: true).toJson(),
        ).showAchievementsBadge,
        isTrue,
      );
    });
  });
}
