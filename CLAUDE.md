# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

NeoStation is a landscape-only, gamepad-driven Flutter emulation frontend for **Windows, Linux, macOS, and Android** (no web, no iOS). Two existing docs are authoritative and worth reading before non-trivial work:
- `ARCHITECTURE.md` — layered architecture, providers/services/repositories/datasources, code conventions.
- `README.md` — build-time configuration (`--dart-define`), Android signing, CI secrets, vendored packages.

This file captures the commands and the cross-cutting rules that aren't obvious from any single file.

`AGENTS.md` just includes this file (`@CLAUDE.md`), so agents that look for either name get the same instructions.
Personal, machine-specific notes belong in an untracked `CLAUDE.local.md` (already gitignored via `*.local.md`).

## Commands

```bash
flutter pub get
flutter analyze                 # must be clean (no errors/warnings) — CI enforces it
dart format .                   # CI fails on unformatted code (--set-exit-if-changed)
flutter test                    # all tests — CI enforces it
flutter test test/game_service_test.dart                       # a single test file
flutter test test/game_service_test.dart --plain-name "name"   # tests matching a name
```

CI (`.github/workflows/build-and-deploy.yml`) runs format check + analyze + test before the platform build matrix.

Run/build need build-time secrets via `--dart-define` (`SCREENSCRAPER_DEV_ID`, `SCREENSCRAPER_DEV_PASSWORD`) — without them, ScreenScraper features degrade but the app still runs. RetroAchievements has no build-time key: each user signs in with their own web API key at runtime. See README for the full matrix.

```bash
flutter run   --dart-define=SCREENSCRAPER_DEV_ID=... --dart-define=SCREENSCRAPER_DEV_PASSWORD=...
flutter build apk --release   <same --dart-define flags>
```

There is no release-keystore requirement for local work: if `android/key.properties` is absent, the Android build falls back to debug signing automatically.

## Cross-cutting rules (read multiple files to get right)

**Layer dependency direction is strict** (see ARCHITECTURE.md): UI → providers → services → repositories → datasources. Services must NOT touch `lib/data/datasources/` directly — go through a repository. Repositories are the only layer allowed to call `SqliteService`/datasources. Cloud-save sync goes through the provider-agnostic `lib/sync/` layer (`SyncManager` + `ISyncProvider`), with NeoSync as the adapter under `sync/providers/`.

**Database schema changes touch two files and several queries:**
- **New columns go in a versioned migration, not the on-launch ALTER pattern** (maintainer's rule, PR #57). Add an idempotent step to the `migrateToVersion` switch in `lib/data/datasources/sqlite_migrations.dart` and bump `_databaseVersion` in `lib/data/datasources/sqlite_service.dart`. Also add the column to the `CREATE TABLE` in `sqlite_service.dart` so fresh installs get it. The defensive `_ensure*Columns` methods (which run on every launch and ALTER-add missing columns) are a legacy safety net — don't rely on them for new work.
- A new `user_system_settings` column must also be **selected in every system-loading query** or it silently reads as default. There are several: `loadSystemsFromDb`, `getUserDetectedSystems`, `getAllSystems`, and the explicit column read in `getSystemByFolderName` (which `copyWith`s settings onto the cached model). Thread it through all of them, plus `SystemModel` (`fromJson`/`toJson`/`copyWith`) and a `SystemRepository`/`SqliteService` setter.
- The downgrade path **recreates the database** (`_onDowngrade`), so running a lower-`_databaseVersion` build over a newer database wipes local data — relevant when switching branches on a test device.

**Branch merges must not collide migration version numbers — renumber, never overwrite.** Two branches can independently add `case N`/`_migrateToVersionN` with the same `N` and different content. When a device migrates while on branch A, then the branches merge and main's `case N` (different content) is skipped because the DB is already past version N — leaving the column missing and every query that references it failing with "no such column". Merge conflicts in `sqlite_migrations.dart`/`sqlite_service.dart` are the symptom to look for. When that happens:
- **Resolve the conflict by renumbering, not by deleting either side.** Pick a number **above the highest one already in use anywhere** (`git log -1 origin/main --format=%H` then grep its `_migrateToVersionNNN`; take the max + 1). Each branch's work gets its own slot: e.g. main keeps v111-v114, the feature branch's NeoSync migrations move to v115/v116/v117. Keep both contents.
- **Wire the renumbered slot into the `migrateToVersion` switch** and bump `_databaseVersion` to the new max.
- **Write an idempotent backfill migration for devices already past the older slot** (the failure mode above). Mirror what main's backfill does: `PRAGMA table_info`, `if (!columns.contains(...))` → `ALTER TABLE ... ADD COLUMN`, no-op otherwise. This is exactly why v118 (`_migrateToVersion118`) exists: databases that migrated on the pre-merge NeoSync branch skipped main's `subfolder_view` v111/v113, so v118 re-adds it idempotently and every fresh install or downgrade/upgrade path stays correct.
- **Never assume a migration ran.** The DB's version is a floor, not a guarantee each intermediate migration executed: a device can skip a `case` because its DB was already past that number when it first saw this binary. New columns that other code depends on should therefore be guarded (`if (!columns.contains(...))`) in their migration so a missed step doesn't brick the app — and when the merge gap is unavoidable, ship the idempotent backfill as the next numbered migration.
- **Test the migration** with an in-memory SQLite DB following the pattern in `test/subfolder_view_backfill_migration_test.dart` / `test/system_view_mode_repair_migration_test.dart`: run `SqliteMigrations.migrateToVersion(db, N)` directly against a schema that deliberately lacks the column (the "old device" case), assert the column now exists, and assert re-running is a no-op.

**Dual-display devices run a second Flutter engine.** `subDisplay()` in `lib/main.dart` (tagged `@pragma('vm:entry-point')`, driven by the `sub_screen` package) renders `lib/screens/secondary_screen/` on dual-screen Android handhelds. It is a separate engine/isolate: it initializes localization and config independently and shares **nothing in memory** with the main engine — both open the same SQLite database. Any state that must appear on both screens has to be persisted or re-derived, not assumed shared.

**The bottom screen is a separate Android window, so `MainActivity`'s input rules do not reach it.** `SecondaryAppsPresentation` extends `android.app.Presentation`, which is a `Dialog`: cancelable and focusable by default. Tapping the bottom screen focuses that window, and BACK then runs `Dialog.cancel()` -> `FlutterPresentation.dismiss()`, which destroys the secondary engine — the bottom half of the launcher is gone until the app restarts while the top half keeps running. `MainActivity.dispatchKeyEvent`/`onBackPressed` swallow BACK for their own window only. The presentation is therefore `setCancelable(false)` + a BACK-swallowing `dispatchKeyEvent` + `FLAG_NOT_FOCUSABLE`; the last one also stops the bottom display becoming the *top-focused display*, which is what sent HOME (and gamepad keys) to the wrong screen. That is only safe while the secondary UI stays touch-only — it has no text fields or key handling today.

**Reproducing it needs NeoStation set as the default launcher, after a reboot.** Otherwise BACK on that window takes Android 13's predictive-back path, which logs `CoreBackPreview: startBackNavigation ... backType=TYPE_UNDEFINED` and no-ops — so the bug looks random, and neither `adb shell input keyevent 4` nor an edge-swipe gesture reproduces it. As HOME it goes down the classic `KEYCODE_BACK` dispatch instead and dismisses. In logcat the kill is `FvpPlugin: onDetachedFromEngine` -> `ViewRootImpl: doDie` -> `CoreBackPreview: Window{...}: Setting back callback null`, followed by `InputEventReceiver: Attempted to finish an input event but the input event receiver has already been disposed` (a window torn down mid-input-event). On the AYN Thor the bottom screen is **display 4**, and Quickstep's `SecondaryDisplayLauncher` already runs behind the presentation — it is revealed by the dismissal, not launched by it.

**A dock-launched app is revealed by *hiding* that presentation, and the hide looks exactly like the app closing.** `MainActivity.hideSecondaryForApp` hides the panel and arms `ScreenshotAccessibilityService`'s watch, which restores it when the bottom display goes back to its home/launcher (Android gives a normal app no other signal that a window on another display was dismissed). But hiding the panel uncovers `com.android.launcher3/.secondarydisplay.SecondaryDisplayLauncher` sitting behind it and fires `TYPE_WINDOWS_CHANGED` before the launched app has drawn, so a plain "top window on that display is a launcher -> restore" test fires ~40ms after the launch and puts the panel straight back over the app: it flashes and is gone, while `dumpsys activity activities` still shows the app as `topResumedActivity` on display 4 (it was never killed, just covered). The watch is therefore two-phase — it arms only once a non-home window has taken that display — plus a 10s watchdog in `MainActivity` for a launch that never lands, and `onResume` must not restore while a watch is armed: a dock app runs on the *other* display, so this activity resuming says nothing about whether it closed.

**Android ROM paths are SAF content URIs, not filesystem paths.** `GameModel.romPath` on Android looks like `content://…/document/primary%3Aemu%2Froms%2Fnes%2FGame.zip` (separators URL-encoded as `%2F`). Desktop uses plain paths. Any path parsing (subfolder/directory logic) must handle the URL-encoded SAF form. **Test path logic on a device, not just desktop** — unit tests use plain paths and won't catch this.

**Localization is custom and map-based** (the `flutter_localization` package, not gen-l10n/ARB). Adding a string requires: a `static const String` key in `lib/l10n/app_locale.dart`, then a value in **every** `lib/l10n/app_locale_<lang>.dart` file (12 languages: de, en, es, fr, id, it, ja, ko, pt, ru, zh, zh_hant). A missing key in any file is an analyzer error.

**Every user-facing string goes through `AppLocale` — no hardcoded UI text.** This applies to every screen including NeoSync (dashboard, save list, custom folders, plan view, dialogs). Filter/menu labels, hints, buttons, empty states, and interpolated strings must all be localized: define the key + the 12 translations, then use `AppLocale.<key>.getString(context)` (and `.replaceFirst('{placeholder}', value)` for interpolation). Strings with parameters keep the `{name}` placeholder form. Log messages (`_log.*`) and internal-only strings are exempt. The analyzer does not enforce this — grep for `Text('...')`, `label: '...'`, `hintText: '...'`, `title: '...'`, and `subtitle: '...'` with capitalized/long literals to catch leaks (the `lib/screens/neo_sync_screen/` directory is a known hotspot).

**Gamepad navigation is custom** (`lib/utils/gamepad_nav.dart` + `GamepadNavigationManager` layer stack). Screens own their selection index and drive child views via `selectedIndex`; the list/grid/carousel widgets are largely presentational. Every interactive element must be reachable by D-pad/controller, not just touch/mouse; B is the app-wide back/cancel action, including escaping a focused text field. Injected Android `adb input keyevent` D-pad events are NOT picked up by this nav (use `input tap` when scripting the UI).

**Every full-screen route must register a `GamepadNavigationManager` layer** — not just call `_gamepadNav.activate()`. On resume, `GameLaunchService.handleAppResumed()` calls `GamepadNavigationManager.reactivate()`, which wakes the top *registered* layer. A screen that activated its navigator without pushing a layer is invisible to the manager, so returning from a launched app/emulator wakes the screen buried underneath it and two navigators then handle the same button press. That is how the Android apps grid came to launch several apps at once: it launched the focused app while the systems carousel behind it re-entered the system and stacked a second copy of the grid, so each further press launched one more app the user never selected. Push the layer in the same post-frame callback as `initialize()`, and `popLayer` in `dispose()`.

**Android keycode buttons arrive action-encoded and inverted.** On Android (confirmed on the AYN Thor) the gamepads plugin reports keycode-backed buttons with press = `0.0` and release = `1.0` — the opposite of the analog convention. The translator historically un-inverted only the D-pad, so face/shoulder buttons fired on *release* and held modifiers (Select, L1/R1) latched stuck. When adding a button binding, check how that button's value is decoded before assuming `> 0.5` means pressed; press/release edges for modifier keys are read at the raw key level.

**System/emulator definitions live in this repo.** `assets/systems/*.json` is the single source of truth for systems, emulator definitions, and launch arguments — PRs for emulator fixes belong here (the separate `neostation-systems` repo is defunct). The bundled `assets/manifest.json` drives the over-the-air systems update mechanism, so compatible changes reach existing installs without an app release. `assets/data/` SQL files seed the database on first run.

**Prefer JSON over Kotlin for emulator launch fixes (maintainer's architectural rule).** Keep `EmulatorLauncher.kt` emulator-agnostic — do **not** add new conditionals / hardcoded package lists there unless strictly necessary. First try to fix launch behaviour by editing the emulator's `launch_arguments` in its `assets/systems/<sys>.json` — usually swapping the path placeholder is enough:
- `{file.path}` → best-effort real filesystem path (resolves SAF `content://` to a raw path; for emulators that need a real path).
- `{file.localuri}` → keeps a `content://` SAF URI as-is (so `launchGenericIntent` can grant it read permission); falls back to `file://` for bare paths.
- `{file.uri}` → `content://`/`file://` pass through; bare paths → `file://`.
The opt-out from our FileProvider rewrap (for emulators that need the original SAF `content://` URI — e.g. Flycast's `.zip` loading, DraStic) is **config-driven**, not a hardcoded Kotlin package list: set `"keep_saf_uri": true` in the emulator's `android` block in `assets/systems/<sys>.json`. The flag threads through `LauncherService` → `game_service.dart` (method channel) → `EmulatorLauncher.kt`, which keeps the Kotlin emulator-agnostic. Example: issue #50/#66 (DraStic) was fixed by `{file.path}`→`{file.localuri}` **plus** `"keep_saf_uri": true` — no Kotlin change. Only touch `EmulatorLauncher.kt` if a genuinely new mechanism (not just another opt-out emulator) is needed.

**Testing embedded `assets/systems/` changes locally:** the app prefers previously downloaded systems over the bundle unless the bundle's version is higher. To force it to read your local edits, bump `latest_version` in `assets/manifest.json` above whatever value is currently there; on launch you'll see `SystemsUpdateService: bundled vX > cached "Y", clearing cache`.

**Vendored packages** live in `/packages/` (`gamepads*`, `flutter_7zip`) — modified upstream libraries wired in as a pub workspace; prefer fixing there over working around them.

## Conventions

Beyond standard Dart/Flutter (and the items in ARCHITECTURE.md — `Color.withValues(alpha:)` not `withOpacity`, `mounted` guards after `await`, `flutter_screenutil` for all sizing, English comments): widgets `PascalCase`, variables `camelCase`, files `snake_case`. Conventional Commits (`feat:`, `fix:`, …); branches `feature/…`, `fix/…`, `refactor/…`, `docs/…`; PRs use `.github/PULL_REQUEST_TEMPLATE.md`. All user-facing UI text goes through `AppLocale` — never hardcoded strings.

## Commits (per AI_GUIDELINES.md)

- **Never** add a DCO sign-off from an AI (no `git commit -s` / `Signed-off-by:`).
- For significant AI-assisted work, add an `AI-Assisted: NAME:VERSION` trailer (e.g. `AI-Assisted: Claude:Fable-5`). A `Co-Authored-By:` trailer is fine and used in practice.
- Code must pass `dart format`, `flutter analyze` (clean), and `flutter test` (all passing) before commit — CI enforces all three.
