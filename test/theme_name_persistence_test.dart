import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_config_service.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/models/config_model.dart';
import 'package:neostation/repositories/config_repository.dart';

import 'database_test_helper.dart';

/// The theme lives in `user_config.theme_name`, but it has only ever had one
/// real writer: [ThemeProvider], via [ConfigRepository.updateThemeName].
/// [SqliteConfigService.saveConfig] performs a whole-row write from the
/// in-memory [ConfigModel], and nothing updates that model's `themeName` after
/// it is read at launch — so including the column there silently restored the
/// launch-time theme on the next settings change the user made.
void main() {
  group('theme_name is not clobbered by a whole-config save', () {
    final dbHelper = DatabaseTestHelper();

    setUp(() async => dbHelper.setUp());
    tearDown(() async => dbHelper.tearDown());

    test('saveConfig leaves a newly chosen theme alone', () async {
      // Launch: the app boots on 'system' and the provider caches that.
      await ConfigRepository.updateThemeName('system');
      const launchTimeConfig = ConfigModel();

      // The user picks a theme (ThemeProvider writes the column directly).
      await ConfigRepository.updateThemeName('dracula');

      // The user then changes any other setting, which persists the whole
      // in-memory config — still carrying the stale launch-time theme.
      await SqliteConfigService.saveConfig(
        launchTimeConfig.copyWith(sfxEnabled: false),
      );

      expect(await ConfigRepository.getThemeName(), 'dracula');
    });

    test('other preferences in the same save still persist', () async {
      await SqliteConfigService.saveConfig(
        const ConfigModel(appLanguage: 'fr', gameGridColumns: 'XL'),
      );

      final stored = await SqliteService.getUserConfig();
      expect(stored?['app_language'].toString(), 'fr');
      expect(stored?['game_grid_columns'].toString(), 'XL');
    });

    test('a theme survives repeated saves from a stale config', () async {
      await ConfigRepository.updateThemeName('nord');

      const stale = ConfigModel();
      for (var i = 0; i < 3; i++) {
        await SqliteConfigService.saveConfig(stale);
      }

      expect(await ConfigRepository.getThemeName(), 'nord');
    });
  });
}
