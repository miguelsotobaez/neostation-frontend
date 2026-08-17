import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/json_config_service.dart';

/// The bundled-asset floor for the RetroAchievements hashing policy.
///
/// A systems definition downloaded before the policy existed declares none, and
/// a missing policy reads as the permissive default — which would quietly cost
/// NES, SNES and arcade their algorithms for anyone who had ever taken a systems
/// update. Rather than bump `assets/manifest.json` and prompt every user in the
/// fleet for a systems download that does nothing on their build, the loader
/// reads that one field out of the bundled copy of the same system.
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
}
