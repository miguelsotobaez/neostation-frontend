import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/json_config_service.dart';

/// The bundled-asset floor for the RetroAchievements hashing policy.
///
/// The policy names algorithms implemented in this binary, so the copy that
/// shipped with the binary is the one that agrees with it — while every other
/// field in a systems definition is better taken from a downloaded update.
/// Rather than bump `assets/manifest.json` and prompt every user in the fleet
/// for a systems download, the loader resolves this one field on its own.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = JsonConfigService.instance;

  test('reads the policy out of a bundled definition', () async {
    expect(await service.bundledRaHash('nes.json'), {
      'algo': 'nes',
      'mode': 'hash_only',
    });
  });

  test('reads the corrected policy for a hack folder', () async {
    // The folder that was in none of the three lists this replaced.
    expect(await service.bundledRaHash('nes-hacks.json'), {
      'algo': 'nes',
      'mode': 'hash_only',
    });
  });

  test('a system that declares no policy yields null, not a guess', () async {
    // Falling through to null is what leaves RaHashPolicy.fallback in place.
    expect(await service.bundledRaHash('music.json'), isNull);
  });

  test('an unknown file is null rather than a throw', () async {
    expect(await service.bundledRaHash('not-a-system.json'), isNull);
  });

  group('choosing between a cached and a bundled policy', () {
    const cached = {'algo': 'file', 'mode': 'filename_fallback'};
    const bundled = {'algo': 'psx', 'mode': 'hash_only'};

    test('a tie goes to the bundle, which is what ships the algorithm', () {
      // The steady state for anyone who has ever taken a systems update: the
      // cached version equals the version the next release bundles, because
      // the remote manifest is the bundled one. Preferring the cache here is
      // how the disc policies failed to reach a device that had a cache.
      expect(
        JsonConfigService.resolveRaHashPolicy(
          cached: cached,
          bundled: bundled,
          preferBundled: true,
        ),
        bundled,
      );
    });

    test('a genuinely newer cache wins, so a fix can ship as data', () {
      expect(
        JsonConfigService.resolveRaHashPolicy(
          cached: cached,
          bundled: bundled,
          preferBundled: false,
        ),
        cached,
      );
    });

    test('a cached definition with no policy falls back either way', () {
      // A definition downloaded before the policy existed declares none, and a
      // missing policy reads as the permissive default — which would cost NES,
      // SNES and arcade their algorithms.
      for (final preferBundled in [true, false]) {
        expect(
          JsonConfigService.resolveRaHashPolicy(
            cached: null,
            bundled: bundled,
            preferBundled: preferBundled,
          ),
          bundled,
          reason: 'preferBundled: $preferBundled',
        );
      }
    });

    test('a system only the cache knows keeps its own policy', () {
      // No bundled counterpart to consult: a system introduced by an update.
      expect(
        JsonConfigService.resolveRaHashPolicy(
          cached: cached,
          bundled: null,
          preferBundled: true,
        ),
        cached,
      );
    });

    test('neither declaring one stays null, not a guess', () {
      expect(
        JsonConfigService.resolveRaHashPolicy(
          cached: null,
          bundled: null,
          preferBundled: true,
        ),
        isNull,
      );
    });
  });
}
