<!-- PR title must follow Conventional Commits — e.g. `fix(android): stop double launches`.
     Release notes are generated from it. Type list: CONTRIBUTING.md.
     If AI tooling wrote a significant part of this, say so below and add an
     `AI-Assisted: NAME:VERSION` trailer to your commits. Never sign commits as an AI. -->

# Description

<!-- What changes, and why. -->

Closes #

## Steps to Verify

<!-- Required for bug fixes. Preconditions first (which system, how many games,
     which device), then numbered steps someone else can follow. -->

**Preconditions:**

1.

## Tested on

<!-- Name the device. Desktop-only testing does not catch Android SAF path bugs. -->

- [ ] Android — device:
- [ ] Linux — device:
- [ ] Windows
- [ ] macOS
- [ ] Not runtime-tested — why:

## Checklist

- [ ] `dart format .` — no diff
- [ ] `flutter analyze` — clean (no errors *or* warnings)
- [ ] `flutter test` — all passing
- [ ] Tests added or updated
- [ ] No secrets, credentials, or personal data in the diff (including tests and fixtures)
- [ ] New assets have compatible licenses

<details>
<summary><b>Extra checks — expand if this PR touches strings, the database, navigation, Android paths, or emulator launching</b></summary>

**User-facing text**
- [ ] New keys in `lib/l10n/app_locale.dart` and a value in **all 12** `app_locale_<lang>.dart` files
- [ ] No hardcoded UI strings — everything goes through `AppLocale`

**The database**
- [ ] Column added to the versioned migration in `sqlite_migrations.dart` **and** the `CREATE TABLE` in `sqlite_service.dart`
- [ ] Migration number is above every slot in use on any open branch, not just `main` + 1
- [ ] Migration is idempotent (`PRAGMA table_info` guard) and has a test
- [ ] `_databaseVersion` bumped; new column selected in *every* system-loading query

**Navigation or a new screen**
- [ ] Every interactive element is reachable by D-pad, not just touch/mouse
- [ ] Full-screen routes push a `GamepadNavigationManager` layer in `initialize()` and pop it in `dispose()`
- [ ] B cancels / goes back, including out of a focused text field

**Android**
- [ ] Path logic handles SAF `content://` URIs (`%2F`-encoded), not just desktop paths
- [ ] Verified on a device, not only on desktop

**`assets/systems/` or emulator launching**
- [ ] Fixed in JSON (`launch_arguments`, `keep_saf_uri`) rather than `EmulatorLauncher.kt` where possible
- [ ] `assets/manifest.json` version bumped if this should reach existing installs OTA

</details>

## Screenshots / video

<!-- Before and after for any visual change. Delete if not applicable. -->
