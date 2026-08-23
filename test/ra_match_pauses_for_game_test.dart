import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/game/game_session_manager.dart';
import 'package:neostation/services/retroachievements_hash_service.dart';

import 'database_test_helper.dart';

/// Launching a game stops a library-wide RetroAchievements pass.
///
/// Hashing reads whole ROMs off storage. On a handheld, doing that while an
/// emulator is running is a worse trade than finishing the pass later — and
/// the pass loses nothing by stopping, because its candidates are "ROMs with
/// no hash", so whoever restarts it picks up exactly where it left off.
///
/// This matters most for the startup pass, which the user did not ask for at
/// that moment and which on an unmatched library runs for minutes.
void main() {
  final dbHelper = DatabaseTestHelper();
  late dynamic db;

  setUp(() async {
    db = await dbHelper.setUp();
    await db.execute(
      "INSERT INTO app_systems (id, real_name, folder_name, ra_id, multidisc)"
      " VALUES ('nes', 'NES', 'nes', '7', 0)",
    );
    for (final name in ['A.nes', 'B.nes', 'C.nes', 'D.nes']) {
      await db.execute(
        "INSERT INTO user_roms (filename, rom_path, app_system_id) "
        "VALUES ('$name', '/roms/nes/$name', 'nes')",
      );
    }
  });

  tearDown(() async {
    // Global launch state: leave it as we found it or the next test starts
    // inside a launch window.
    GameSessionManager.clearLaunchPending();
    await dbHelper.tearDown();
  });

  test('a launch stops an in-flight pass after the current ROM', () async {
    final result = await RetroAchievementsHashService.rematchLibrary(
      onProgress: (processed, total, label) {
        // Exactly what the user does: starts a game while the pass is running.
        if (processed == 0) GameSessionManager.beginLaunchPending();
      },
    );

    expect(result.cancelled, isTrue);
    expect(
      result.processed,
      lessThan(result.total),
      reason: 'the pass should stop, not run to the end of the library',
    );
    expect(RetroAchievementsHashService.isRematchRunning, isFalse);
  });

  test('the stopped pass resumes from where it left off', () async {
    final firstRun = await RetroAchievementsHashService.rematchLibrary(
      onProgress: (processed, total, label) {
        if (processed == 0) GameSessionManager.beginLaunchPending();
      },
    );
    GameSessionManager.clearLaunchPending();

    // The ROMs the first run parked are excluded from the candidate query, so
    // a second run sees only what is left.
    final secondRun = await RetroAchievementsHashService.rematchLibrary();

    expect(secondRun.total, firstRun.total - firstRun.processed);
  });

  test('a launch with no pass running latches nothing', () async {
    GameSessionManager.beginLaunchPending();
    GameSessionManager.clearLaunchPending();

    // If the pause request had latched, this pass would abort immediately.
    final result = await RetroAchievementsHashService.rematchLibrary();

    expect(result.cancelled, isFalse);
    expect(result.processed, result.total);
  });
}
