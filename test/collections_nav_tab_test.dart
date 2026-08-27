import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/config_model.dart';
import 'package:neostation/utils/nav_tabs.dart';

void main() {
  group('NavTab.collections', () {
    test('is defined in NavTab enum with correct spec', () {
      expect(NavTab.values.contains(NavTab.collections), isTrue);

      final spec = navTabSpec(NavTab.collections);
      expect(spec.labelKey, AppLocale.collections);
      expect(spec.iconData, Symbols.collections_bookmark_rounded);
      expect(spec.isHidable, isTrue);
      expect(spec.settingsTitleKey, AppLocale.showCollectionsTab);
      expect(spec.settingsSubtitleKey, AppLocale.showCollectionsTabSubtitle);
    });

    test('is visible by default in visibleNavTabs', () {
      const config = ConfigModel();
      expect(config.hideTabCollections, isFalse);

      final visible = visibleNavTabs(config);
      expect(visible.contains(NavTab.collections), isTrue);
    });

    test('is excluded from visibleNavTabs when hidden', () {
      const config = ConfigModel(hideTabCollections: true);
      expect(config.hideTabCollections, isTrue);

      final visible = visibleNavTabs(config);
      expect(visible.contains(NavTab.collections), isFalse);
    });

    test('is present in hidableNavTabs list', () {
      final hidable = hidableNavTabs();
      expect(hidable.contains(NavTab.collections), isTrue);
    });

    test('withHidden updates ConfigModel.hideTabCollections correctly', () {
      const config = ConfigModel();
      final spec = navTabSpec(NavTab.collections);

      final hiddenConfig = spec.withHidden!(config, true);
      expect(hiddenConfig.hideTabCollections, isTrue);

      final restoredConfig = spec.withHidden!(hiddenConfig, false);
      expect(restoredConfig.hideTabCollections, isFalse);
    });
  });
}
