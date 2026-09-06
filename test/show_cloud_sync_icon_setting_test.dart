import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_config_service.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/models/config_model.dart';

import 'database_test_helper.dart';

/// The cloud-save mark is on by default, so the write path is only half of it:
/// what has to hold is that turning it *off* comes back off. A column that is
/// written and never read has happened twice in this area already, and in both
/// cases the write test passed on its own.
void main() {
  final dbHelper = DatabaseTestHelper();

  setUp(() async => dbHelper.setUp());
  tearDown(() async => dbHelper.tearDown());

  group('show cloud sync icon setting', () {
    test('a fresh config has the mark on', () {
      expect(const ConfigModel().showCloudSyncIcon, isTrue);
    });

    test(
      'a database row written before the setting existed reads as on',
      () async {
        // No value ever written for the column: its default stands in, and it
        // has to preserve the behaviour that shipped before the setting.
        await SqliteService.saveUserConfig(appLanguage: 'en');

        final loaded = await SqliteConfigService.loadConfig();

        expect(loaded.showCloudSyncIcon, isTrue);
      },
    );

    test('turning it off survives a save and reload', () async {
      await SqliteConfigService.saveConfig(
        const ConfigModel(showCloudSyncIcon: false),
      );

      final loaded = await SqliteConfigService.loadConfig();

      expect(loaded.showCloudSyncIcon, isFalse);
    });

    test('turning it back on survives a save and reload', () async {
      await SqliteConfigService.saveConfig(
        const ConfigModel(showCloudSyncIcon: false),
      );
      await SqliteConfigService.saveConfig(
        const ConfigModel(showCloudSyncIcon: true),
      );

      final loaded = await SqliteConfigService.loadConfig();

      expect(loaded.showCloudSyncIcon, isTrue);
    });

    test('the setting round-trips through JSON in both key forms', () {
      final asCamel = ConfigModel.fromJson(const {'showCloudSyncIcon': false});
      final asColumn = ConfigModel.fromJson(const {'show_cloud_sync_icon': 0});
      final absent = ConfigModel.fromJson(const {});

      expect(asCamel.showCloudSyncIcon, isFalse);
      expect(asColumn.showCloudSyncIcon, isFalse);
      expect(absent.showCloudSyncIcon, isTrue);
      expect(
        ConfigModel.fromJson(
          const ConfigModel(showCloudSyncIcon: false).toJson(),
        ).showCloudSyncIcon,
        isFalse,
      );
    });
  });
}
