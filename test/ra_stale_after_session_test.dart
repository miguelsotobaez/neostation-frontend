import 'package:flutter_test/flutter_test.dart';

import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/retro_achievements_game_info.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/providers/retro_achievements_provider.dart';
import 'package:neostation/services/game/game_session_manager.dart';

/// The player earns achievements in the emulator, not in NeoStation, so every
/// RetroAchievements read the app is holding is stale the moment a session
/// ends. Both caches that serve those reads live for the whole app session and
/// were only ever cleared on sign-out, so the achievement list and the
/// dashboard kept showing pre-session state until the app was restarted.
void main() {
  const system = SystemModel(
    folderName: 'gg',
    realName: 'Game Gear',
    iconImage: '',
    color: '#7E57C2',
  );

  // romPath stays null so ending the session touches no repository: the
  // playtime write and the RomM record are both skipped for a session with no
  // path and no elapsed seconds, which leaves the notification as the only
  // thing under test.
  const game = GameModel(
    romname: 'Sonic The Hedgehog.gg',
    realname: 'Sonic The Hedgehog',
    name: 'Sonic The Hedgehog',
    year: '1991',
    developer: '',
    publisher: '',
    genre: '',
    players: '1',
    rating: 0,
  );

  Future<void> playAndExit() async {
    GameSessionManager.registerGameLaunch(system, game);
    await GameSessionManager.endGameSession();
  }

  group('cached RetroAchievements reads after a game session', () {
    test('a finished session invalidates the provider', () async {
      final provider = RetroAchievementsProvider();
      addTearDown(provider.dispose);

      final before = provider.cacheGeneration;
      await playAndExit();

      expect(
        provider.cacheGeneration,
        greaterThan(before),
        reason: 'ending a session must drop what the provider cached',
      );
    });

    test('the per-game achievement cache is emptied', () async {
      final provider = RetroAchievementsProvider();
      addTearDown(provider.dispose);

      // The map is the live cache, so seeding it stands in for having opened a
      // game's achievements before playing it.
      provider.gameInfoCache[1516] = GameInfoAndUserProgress.fromJson(const {
        'ID': 1516,
        'Title': 'Sonic The Hedgehog',
      });
      expect(provider.gameInfoCache, isNotEmpty);

      await playAndExit();

      expect(provider.gameInfoCache, isEmpty);
    });

    test('a finished session marks the dashboard stale immediately', () async {
      final provider = RetroAchievementsProvider();
      addTearDown(provider.dispose);

      provider.markDashboardAttempted();
      expect(
        provider.dashboardIsStale,
        isFalse,
        reason: 'a load that just finished is inside the staleness window',
      );

      await playAndExit();

      expect(
        provider.dashboardIsStale,
        isTrue,
        reason:
            'a finished session has to beat the staleness window, not '
            'wait it out',
      );
    });

    test('an unread dashboard starts stale', () {
      final provider = RetroAchievementsProvider();
      addTearDown(provider.dispose);

      expect(provider.dashboardIsStale, isTrue);
    });

    test('listeners are told, so a mounted dashboard can reload', () async {
      final provider = RetroAchievementsProvider();
      addTearDown(provider.dispose);

      var notified = 0;
      void listener() => notified++;
      provider.addListener(listener);
      addTearDown(() => provider.removeListener(listener));

      await playAndExit();

      expect(notified, greaterThan(0));
    });

    test('a disposed provider is not notified', () async {
      final provider = RetroAchievementsProvider();
      provider.dispose();

      // Without the unsubscribe in dispose this throws: notifyListeners on a
      // disposed ChangeNotifier is an error, and the session manager holds a
      // static reference that outlives any one provider.
      await expectLater(playAndExit(), completes);
    });
  });

  group('session-end listeners', () {
    test('one listener throwing does not stop the rest', () async {
      var second = 0;
      void bad() => throw StateError('boom');
      void good() => second++;

      GameSessionManager.addSessionEndListener(bad);
      GameSessionManager.addSessionEndListener(good);
      addTearDown(() {
        GameSessionManager.removeSessionEndListener(bad);
        GameSessionManager.removeSessionEndListener(good);
      });

      await playAndExit();

      expect(second, 1);
    });

    test('a removed listener stops being called', () async {
      var calls = 0;
      void listener() => calls++;

      GameSessionManager.addSessionEndListener(listener);
      await playAndExit();
      expect(calls, 1);

      GameSessionManager.removeSessionEndListener(listener);
      await playAndExit();
      expect(calls, 1);
    });

    test('registering the same listener twice still calls it once', () async {
      var calls = 0;
      void listener() => calls++;

      GameSessionManager.addSessionEndListener(listener);
      GameSessionManager.addSessionEndListener(listener);
      addTearDown(() => GameSessionManager.removeSessionEndListener(listener));

      await playAndExit();

      expect(calls, 1);
    });
  });
}
