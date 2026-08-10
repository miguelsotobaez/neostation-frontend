import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:neostation/l10n/app_locale.dart';
import 'package:neostation/models/config_model.dart';

/// Identity of a top-level navigation tab (the L1/R1 strip in the header).
///
/// The ordinal **is** the canonical tab index used by `AppScreenState`
/// (`_selectedTabIndex`, `_buildCurrentTabContent`, the secondary-display tab
/// names). Append new tabs at the end — inserting one renumbers every existing
/// tab and silently repoints all of that dispatch.
enum NavTab { systems, search, sync, achievements, scraper, romm, settings }

/// Static description of one navigation tab: how it is drawn, whether the user
/// may hide it, and how that preference is read and written.
class NavTabSpec {
  const NavTabSpec({
    required this.icon,
    required this.labelKey,
    this.iconData,
    this.hidden,
    this.withHidden,
    this.settingsTitleKey,
    this.settingsSubtitleKey,
  });

  /// Asset drawn in the header strip. Use [iconData] when no asset exists.
  final String icon;

  /// Material symbol fallback for tabs with no webp asset.
  final IconData? iconData;

  /// [AppLocale] key for the tab's display name.
  final String labelKey;

  /// Reads this tab's "hidden" preference. `null` means the tab can never be
  /// hidden — that is the default for any tab not wired up here.
  final bool Function(ConfigModel config)? hidden;

  /// Returns a copy of [config] with this tab's "hidden" preference set.
  final ConfigModel Function(ConfigModel config, bool hidden)? withHidden;

  /// [AppLocale] keys for this tab's row in General settings.
  final String? settingsTitleKey;
  final String? settingsSubtitleKey;

  /// Whether the user can toggle this tab's visibility.
  bool get isHidable => hidden != null && withHidden != null;
}

/// Fallback for a [NavTab] with no entry in [navTabSpecs].
///
/// It has no [NavTabSpec.hidden] predicate, so an unregistered tab renders and
/// stays permanently visible rather than disappearing — the safe failure for a
/// tab added in a future version before its toggle is wired up.
const NavTabSpec _fallbackSpec = NavTabSpec(
  icon: 'assets/images/icons/grids.webp',
  labelKey: AppLocale.systems,
);

/// Systems and Settings are deliberately absent a [NavTabSpec.hidden]
/// predicate: Systems is the home tab, and Settings must stay reachable or a
/// user who hid everything else could never turn it back on.
const Map<NavTab, NavTabSpec> navTabSpecs = {
  NavTab.systems: NavTabSpec(
    icon: 'assets/images/icons/grids.webp',
    labelKey: AppLocale.systems,
  ),
  NavTab.search: NavTabSpec(
    icon: '',
    labelKey: AppLocale.searchTitle,
    iconData: Symbols.search_rounded,
    hidden: _hideTabSearch,
    withHidden: _withHideTabSearch,
    settingsTitleKey: AppLocale.showSearchTab,
    settingsSubtitleKey: AppLocale.showSearchTabSubtitle,
  ),
  NavTab.sync: NavTabSpec(
    icon: 'assets/images/icons/cloud-add.webp',
    labelKey: AppLocale.neoSync,
    hidden: _hideTabSync,
    withHidden: _withHideTabSync,
    settingsTitleKey: AppLocale.showSyncTab,
    settingsSubtitleKey: AppLocale.showSyncTabSubtitle,
  ),
  NavTab.achievements: NavTabSpec(
    icon: 'assets/images/icons/enhance-prize.webp',
    labelKey: AppLocale.achievements,
    hidden: _hideTabAchievements,
    withHidden: _withHideTabAchievements,
    settingsTitleKey: AppLocale.showAchievementsTab,
    settingsSubtitleKey: AppLocale.showAchievementsTabSubtitle,
  ),
  NavTab.scraper: NavTabSpec(
    icon: 'assets/images/icons/box-search.webp',
    labelKey: AppLocale.scraping,
    hidden: _hideTabScraper,
    withHidden: _withHideTabScraper,
    settingsTitleKey: AppLocale.showScraperTab,
    settingsSubtitleKey: AppLocale.showScraperTabSubtitle,
  ),
  NavTab.romm: NavTabSpec(
    icon: 'assets/images/icons/romm-light.svg',
    labelKey: AppLocale.rommLibrary,
    hidden: _hideTabRomm,
    withHidden: _withHideTabRomm,
    settingsTitleKey: AppLocale.showRommTab,
    settingsSubtitleKey: AppLocale.showRommTabSubtitle,
  ),
  NavTab.settings: NavTabSpec(
    icon: 'assets/images/icons/setting.webp',
    labelKey: AppLocale.settings,
  ),
};

// Torn out as top-level functions so [navTabSpecs] can stay `const`.
bool _hideTabSync(ConfigModel c) => c.hideTabSync;
bool _hideTabAchievements(ConfigModel c) => c.hideTabAchievements;
bool _hideTabScraper(ConfigModel c) => c.hideTabScraper;
bool _hideTabRomm(ConfigModel c) => c.hideTabRomm;
bool _hideTabSearch(ConfigModel c) => c.hideTabSearch;

ConfigModel _withHideTabSync(ConfigModel c, bool hidden) =>
    c.copyWith(hideTabSync: hidden);
ConfigModel _withHideTabAchievements(ConfigModel c, bool hidden) =>
    c.copyWith(hideTabAchievements: hidden);
ConfigModel _withHideTabScraper(ConfigModel c, bool hidden) =>
    c.copyWith(hideTabScraper: hidden);
ConfigModel _withHideTabRomm(ConfigModel c, bool hidden) =>
    c.copyWith(hideTabRomm: hidden);
ConfigModel _withHideTabSearch(ConfigModel c, bool hidden) =>
    c.copyWith(hideTabSearch: hidden);

/// Description of [tab], never null — see [_fallbackSpec].
NavTabSpec navTabSpec(NavTab tab) => navTabSpecs[tab] ?? _fallbackSpec;

/// Tabs the user should see, in canonical order.
///
/// A tab is visible unless it has a registered hide-predicate that says
/// otherwise, so an unregistered (i.e. newly added) tab is visible by default.
List<NavTab> visibleNavTabs(ConfigModel config) => NavTab.values
    .where((tab) => !(navTabSpec(tab).hidden?.call(config) ?? false))
    .toList(growable: false);

/// Tabs the user can toggle, in canonical order. Drives the General settings
/// rows, so wiring a future tab's spec is all it takes to give it a toggle.
List<NavTab> hidableNavTabs() => NavTab.values
    .where((tab) => navTabSpec(tab).isHidable)
    .toList(growable: false);

/// Most tab slots the header strip shows at once. With more visible tabs than
/// this, the strip scrolls; with this many or fewer it renders exactly as a
/// static strip and never scrolls.
const int maxVisibleNavTabSlots = 6;

/// First slot shown by the scrolling strip after selection moves to
/// [selectedSlot].
///
/// Minimal-scroll windowing: the window is untouched while the selection stays
/// inside it and shifts just far enough to include the selection when it walks
/// off either edge, so cycling with the bumpers scrolls one slot at a time
/// (with a jump only on wrap-around). A [selectedSlot] of -1 (selected tab
/// hidden by a config change) keeps the current window rather than snapping
/// anywhere. The result is always clamped so the window never shows blank
/// slots past either end.
int navTabWindowStart({
  required int windowStart,
  required int selectedSlot,
  required int tabCount,
  int maxSlots = maxVisibleNavTabSlots,
}) {
  if (tabCount <= maxSlots) return 0;
  var start = windowStart;
  if (selectedSlot >= 0) {
    if (selectedSlot < start) start = selectedSlot;
    if (selectedSlot > start + maxSlots - 1) {
      start = selectedSlot - maxSlots + 1;
    }
  }
  return start.clamp(0, tabCount - maxSlots);
}
