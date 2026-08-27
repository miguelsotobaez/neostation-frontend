# Implementation Plan - Collections Feature

Add a new **Collections** feature to NeoStation as outlined in [Issue #10](https://github.com/misobadev/neostation-frontend/issues/10). This feature allows users to create custom game collections across different systems (e.g. "Mario Series", "Metroidvania", "Fighting Classics"), browse them in a dedicated navigation tab, launch games directly from collections, manage games via an Add/Manage Games menu, and toggle the tab visibility in Settings.

## User Review Required

> [!IMPORTANT]
> - **Database Migration**: Schema version bumped from 149 to 150 (`v150`), creating `user_collections` and `user_collection_roms` junction table, and adding `hide_tab_collections` to `user_config`.
> - **Navigation Tab**: Added `NavTab.collections` to the top header bar with `Symbols.collections_bookmark_rounded` icon and full gamepad navigation (L1/R1 cycling, focus layer management).
> - **Settings Toggle**: "Show Collections tab" toggle added to General Settings (automatically rendered via `hidableNavTabs()` and `NavTabSpec`).

## Proposed Changes

Grouped by component layer following NeoStation's architectural guidelines:

---

### 1. Database & Configuration Layer

#### [MODIFY] [sqlite_service.dart](file:///Users/gsk/Code/neostation-frontend/lib/data/datasources/sqlite_service.dart)
- Bump `_databaseVersion` from 149 to 150.
- Update `user_config` table definition in `_createUserTables` to include `hide_tab_collections INTEGER DEFAULT 0`.
- Add `CREATE TABLE IF NOT EXISTS user_collections` (`id`, `name`, `description`, `icon`, `color`, `created_at`, `updated_at`) and `CREATE TABLE IF NOT EXISTS user_collection_roms` (`id`, `collection_id`, `rom_path`, `display_order`, `added_at`, `UNIQUE(collection_id, rom_path)`, `FOREIGN KEY(collection_id) REFERENCES user_collections(id) ON DELETE CASCADE`).
- Add indexes on `user_collection_roms(collection_id)` and `user_collection_roms(rom_path)`.
- Update `saveUserConfig` to support `hideTabCollections`.
- Implement raw database CRUD methods:
  - `createCollection`, `updateCollection`, `deleteCollection`, `getCollections`, `getCollection`, `getGamesForCollection`, `addGamesToCollection`, `removeGamesFromCollection`, `setGamesForCollection`, `isGameInCollection`, `getCollectionIdsForGame`.

#### [MODIFY] [sqlite_migrations.dart](file:///Users/gsk/Code/neostation-frontend/lib/data/datasources/sqlite_migrations.dart)
- Add `case 150: await _migrateToVersion150(db); break;` to `migrateToVersion`.
- Implement `_migrateToVersion150(Database db)`:
  - Idempotently add `hide_tab_collections` to `user_config` if not present.
  - Create `user_collections` and `user_collection_roms` tables if not present.
  - Create indexes if not present.

#### [MODIFY] [config_model.dart](file:///Users/gsk/Code/neostation-frontend/lib/models/config_model.dart)
- Add `final bool hideTabCollections;` (defaults to `false` = visible).
- Update `fromJson`, `toJson`, `copyWith`, and `empty`.

#### [MODIFY] [sqlite_config_service.dart](file:///Users/gsk/Code/neostation-frontend/lib/data/datasources/sqlite_config_service.dart)
- Read `hide_tab_collections` in `loadUserConfig`.
- Write `hideTabCollections` in `saveConfig`.

---

### 2. Data Models, Repositories & State Layer

#### [NEW] [collection_model.dart](file:///Users/gsk/Code/neostation-frontend/lib/models/collection_model.dart)
- Entity representation for a user collection:
  - `id`: int
  - `name`: String
  - `description`: String?
  - `icon`: String?
  - `color`: String?
  - `romCount`: int
  - `coverRomPaths`: List<String> (top 4 ROM paths for 2x2 collage preview)
  - `createdAt`, `updatedAt`: DateTime?
  - `fromMap`, `toMap`, `copyWith`

#### [NEW] [collection_repository.dart](file:///Users/gsk/Code/neostation-frontend/lib/repositories/collection_repository.dart)
- Repository abstraction for collections data operations:
  - `getCollections()`, `getCollection(int id)`, `createCollection(...)`, `updateCollection(...)`, `deleteCollection(int id)`, `getGamesForCollection(int id)`, `setGamesForCollection(int id, List<String> romPaths)`, `addGamesToCollection(int id, List<String> romPaths)`, `removeGamesFromCollection(int id, List<String> romPaths)`, `getCollectionIdsForGame(String romPath)`.

#### [NEW] [collection_provider.dart](file:///Users/gsk/Code/neostation-frontend/lib/providers/collection_provider.dart)
- `ChangeNotifier` state management:
  - `List<CollectionModel> collections`
  - `bool isLoading`
  - `CollectionModel? activeCollection`
  - `List<GameModel> activeCollectionGames`
  - Lifecycle methods: `loadCollections()`, `createCollection(...)`, `updateCollection(...)`, `deleteCollection(...)`, `loadCollectionGames(int id)`, `addGamesToCollection(...)`, `removeGameFromCollection(...)`, `setCollectionGames(...)`.

#### [MODIFY] [main.dart](file:///Users/gsk/Code/neostation-frontend/lib/main.dart)
- Register `CollectionProvider` in `MultiProvider` tree.

---

### 3. Navigation & App Integration

#### [MODIFY] [nav_tabs.dart](file:///Users/gsk/Code/neostation-frontend/lib/utils/nav_tabs.dart)
- Add `collections` to `enum NavTab { systems, search, collections, sync, achievements, scraper, romm, settings }`.
- Add `NavTab.collections` to `navTabSpecs` with:
  - `iconData: Symbols.collections_bookmark_rounded`
  - `labelKey: AppLocale.collections`
  - `hidden: _hideTabCollections`
  - `withHidden: _withHideTabCollections`
  - `settingsTitleKey: AppLocale.showCollectionsTab`
  - `settingsSubtitleKey: AppLocale.showCollectionsTabSubtitle`
- Implement `_hideTabCollections` and `_withHideTabCollections`.

#### [MODIFY] [app_screen.dart](file:///Users/gsk/Code/neostation-frontend/lib/screens/app_screen.dart)
- Update `AppTabs` constants:
  - `systems = 0`, `search = 1`, `collections = 2`, `sync = 3`, `achievements = 4`, `scraper = 5`, `romm = 6`, `settings = 7`, `count = 8`.
- In `_buildCurrentTabContent()`:
  - Add `case AppTabs.collections: return const CollectionsTab();` (with gamepad nav deactivation handoff).
- In `_updateSecondaryDisplay()`:
  - Add `case AppTabs.collections: tabName = 'Collections'; break;`

---

### 4. UI Layer - Collections Feature

#### [NEW] [collections_tab.dart](file:///Users/gsk/Code/neostation-frontend/lib/screens/collections_screen/collections_tab.dart)
- Root container for the Collections tab.
- Manages view switching between **Collections Overview** (grid of collections) and **Collection Detail View** (games in active collection).
- Integrates `GamepadNavigationManager` layer (`'collections_tab'`).

#### [NEW] [collections_overview.dart](file:///Users/gsk/Code/neostation-frontend/lib/screens/collections_screen/collections_overview.dart)
- Grid layout displaying user collections.
- Includes a dedicated "Create Collection" card and empty state widget when no collections exist.
- Gamepad controls: D-pad to navigate cards, A to open collection, X to create new collection, Y for collection options menu (rename / delete).

#### [NEW] [collection_card.dart](file:///Users/gsk/Code/neostation-frontend/lib/screens/collections_screen/collection_card.dart)
- Clean, theme-integrated collection card with **Accent Color / Banner** styling:
  - Header banner / accent icon pill (`Symbols.collections_bookmark_rounded`).
  - Collection title and game count badge (e.g., "12 games").
  - Smooth gamepad focus state with theme accent glow border and subtle scale animation.
  - Dedicated "+ Create Collection" variant card with dashed accent border.

#### [NEW] [collection_detail_view.dart](file:///Users/gsk/Code/neostation-frontend/lib/screens/collections_screen/collection_detail_view.dart)
- Browsing view for games in the selected collection:
  - Header: Collection title, game count, Back action, Add Games (Y), Options menu.
  - Game List / Grid layout with game details panel (artwork, title, developer, year, rating, description).
  - Launch flow: Press A to launch game via `launchGameWithDialog`.
  - Context menu: Remove from collection, View game details.
  - Press B to return to Collections Overview.

#### [NEW] [create_edit_collection_dialog.dart](file:///Users/gsk/Code/neostation-frontend/lib/screens/collections_screen/create_edit_collection_dialog.dart)
- Modal dialog for creating and renaming collections.
- Text input with on-screen keyboard support, gamepad navigation (A = Confirm, B = Cancel).

#### [NEW] [collection_add_games_dialog.dart](file:///Users/gsk/Code/neostation-frontend/lib/screens/collections_screen/collection_add_games_dialog.dart)
- Full-screen "Add / Manage Games" picker:
  - Search filter bar (by game name).
  - System filter chips (All Systems, NES, SNES, PS1, etc.).
  - Interactive game list with checkboxes for toggling inclusion in the collection.
  - Gamepad navigation (D-pad to move, A to toggle, B to finish).

---

### 5. Localization Layer

#### [MODIFY] [app_locale.dart](file:///Users/gsk/Code/neostation-frontend/lib/l10n/app_locale.dart)
- Add string keys:
  `collections`, `showCollectionsTab`, `showCollectionsTabSubtitle`, `createCollection`, `editCollection`, `deleteCollection`, `deleteCollectionConfirm`, `collectionName`, `collectionNameHint`, `collectionDescription`, `noCollectionsTitle`, `noCollectionsSubtitle`, `emptyCollectionTitle`, `emptyCollectionSubtitle`, `addGames`, `manageGames`, `removeFromCollection`, `gamesCountSingle`, `gamesCountPlural`, `collectionCreated`, `collectionUpdated`, `collectionDeleted`, `gamesAddedToCollection`, `allSystems`, `searchGames`, `addToCollection`, `selectCollections`.

#### [MODIFY] Localization files (all 12 languages)
- [app_locale_en.dart](file:///Users/gsk/Code/neostation-frontend/lib/l10n/app_locale_en.dart)
- [app_locale_es.dart](file:///Users/gsk/Code/neostation-frontend/lib/l10n/app_locale_es.dart)
- [app_locale_de.dart](file:///Users/gsk/Code/neostation-frontend/lib/l10n/app_locale_de.dart)
- [app_locale_fr.dart](file:///Users/gsk/Code/neostation-frontend/lib/l10n/app_locale_fr.dart)
- [app_locale_id.dart](file:///Users/gsk/Code/neostation-frontend/lib/l10n/app_locale_id.dart)
- [app_locale_it.dart](file:///Users/gsk/Code/neostation-frontend/lib/l10n/app_locale_it.dart)
- [app_locale_ja.dart](file:///Users/gsk/Code/neostation-frontend/lib/l10n/app_locale_ja.dart)
- [app_locale_ko.dart](file:///Users/gsk/Code/neostation-frontend/lib/l10n/app_locale_ko.dart)
- [app_locale_pt.dart](file:///Users/gsk/Code/neostation-frontend/lib/l10n/app_locale_pt.dart)
- [app_locale_ru.dart](file:///Users/gsk/Code/neostation-frontend/lib/l10n/app_locale_ru.dart)
- [app_locale_zh.dart](file:///Users/gsk/Code/neostation-frontend/lib/l10n/app_locale_zh.dart)
- [app_locale_zh_hant.dart](file:///Users/gsk/Code/neostation-frontend/lib/l10n/app_locale_zh_hant.dart)

---

### 6. Tests

#### [NEW] [collections_migration_test.dart](file:///Users/gsk/Code/neostation-frontend/test/collections_migration_test.dart)
- In-memory SQLite migration test verifying schema v150 creates `user_collections`, `user_collection_roms`, and adds `hide_tab_collections` to `user_config` without regressions.

#### [NEW] [collection_repository_test.dart](file:///Users/gsk/Code/neostation-frontend/test/collection_repository_test.dart)
- Tests for creating, renaming, deleting collections, adding/removing games, and retrieving collection games.

#### [NEW] [collections_nav_tab_test.dart](file:///Users/gsk/Code/neostation-frontend/test/collections_nav_tab_test.dart)
- Tests verifying `NavTab.collections` spec, visibility toggle, and settings row integration.

#### [MODIFY] [database_test_helper.dart](file:///Users/gsk/Code/neostation-frontend/test/database_test_helper.dart)
- Update mock schema if applicable.

---

## Verification Plan

### Automated Tests
- Run full localization validation:
  ```bash
  flutter test test/app_locale_test.dart
  ```
- Run collections unit and migration tests:
  ```bash
  flutter test test/collections_migration_test.dart
  flutter test test/collection_repository_test.dart
  flutter test test/collections_nav_tab_test.dart
  ```
- Run all existing test suite:
  ```bash
  flutter test
  ```
- Run analyzer check (must be 0 errors, 0 warnings):
  ```bash
  flutter analyze
  ```
- Run code formatter check:
  ```bash
  dart format --output=none --set-exit-if-changed .
  ```

### Manual Verification
- Verify the Collections tab appears in the top navigation strip.
- Verify creating a collection, adding games from different systems via the "Add Games" picker.
- Verify browsing the collection, viewing game details, and launching games.
- Verify editing/deleting collections.
- Verify toggling the Collections tab on/off in Settings > General.
