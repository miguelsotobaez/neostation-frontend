import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/ra_hash_policy.dart';
import 'package:neostation/models/ra_match_candidate.dart';

/// The RetroAchievements hashing policy, and the systems JSON that declares it.
///
/// The policy replaced three hardcoded lists in the hash service that could —
/// and did — disagree with each other: a system could be flagged as
/// hash-matching while the isolate gave it a different algorithm, or gain an
/// algorithm and never be flagged at all. The structural group below is what
/// stops that returning: it is a lint over the data, run by the normal gate.
void main() {
  group('RaHashPolicy parsing', () {
    test('reads the names written in the systems JSON', () {
      final policy = RaHashPolicy.fromNames('nes', 'hash_only');

      expect(policy.algo, RaHashAlgo.nes);
      expect(policy.mode, RaMatchMode.hashOnly);
      expect(policy.isHashOnly, isTrue);
    });

    test('an undeclared policy is the permissive default', () {
      final policy = RaHashPolicy.fromNames(null, null);

      expect(policy, RaHashPolicy.fallback);
      expect(policy.algo, RaHashAlgo.file);
      expect(policy.mode, RaMatchMode.filenameFallback);
      expect(policy.isHashOnly, isFalse);
    });

    test('an unknown algorithm falls back to the whole-file hash', () {
      // An older build reading a systems JSON that gained a new algorithm.
      expect(
        RaHashPolicy.fromNames('gamecube', 'hash_only').algo,
        RaHashAlgo.file,
      );
    });

    test('an unknown mode falls back to allowing the filename guess', () {
      expect(
        RaHashPolicy.fromNames('nes', 'something_else').mode,
        RaMatchMode.filenameFallback,
      );
    });

    test('only the arcade algorithm keeps archives packed', () {
      for (final algo in RaHashAlgo.values) {
        final policy = RaHashPolicy(algo: algo, mode: RaMatchMode.hashOnly);
        expect(
          policy.keepsArchivesPacked,
          algo == RaHashAlgo.arcade,
          reason: '${algo.jsonName} archive handling',
        );
      }
    });
  });

  group('RaMatchCandidate', () {
    test('carries the policy off the candidate row', () {
      final candidate = RaMatchCandidate.fromRow({
        'rom_path': '/roms/nes/Contra.nes',
        'filename': 'Contra.nes',
        'system_folder_name': 'nes',
        'system_ra_id': '7',
        'ra_hash_algo': 'nes',
        'ra_hash_mode': 'hash_only',
      });

      expect(candidate.policy.algo, RaHashAlgo.nes);
      expect(candidate.policy.isHashOnly, isTrue);
    });

    test('a row with no policy columns gets the default', () {
      final candidate = RaMatchCandidate.fromRow({
        'rom_path': '/roms/ps1/Game.chd',
        'filename': 'Game.chd',
        'system_folder_name': 'ps1',
        'system_ra_id': '12',
      });

      expect(candidate.policy, RaHashPolicy.fallback);
    });
  });

  group('assets/systems declares a usable policy', () {
    late Map<String, Map<String, dynamic>> systems;

    setUpAll(() {
      systems = {};
      for (final entity in Directory('assets/systems').listSync()) {
        if (entity is! File || !entity.path.endsWith('.json')) continue;
        final id = entity.uri.pathSegments.last.replaceAll('.json', '');
        systems[id] =
            (json.decode(entity.readAsStringSync())
                    as Map<String, dynamic>)['system']
                as Map<String, dynamic>;
      }
      expect(systems, isNotEmpty, reason: 'no systems JSON found');
    });

    test('every declared algo and mode is a name the app knows', () {
      final algos = RaHashAlgo.values.map((a) => a.jsonName).toSet();
      final modes = RaMatchMode.values.map((m) => m.jsonName).toSet();

      systems.forEach((id, system) {
        final block = system['ra_hash'];
        if (block == null) return;
        expect(algos, contains(block['algo']), reason: '$id.json algo');
        expect(modes, contains(block['mode']), reason: '$id.json mode');
      });
    });

    test('every system RetroAchievements covers declares a policy', () {
      // Without this a new system silently gets the whole-file hash and the
      // filename guess, which is how the -hacks folders went years using the
      // wrong algorithm for their parent platform.
      final missing = <String>[];
      systems.forEach((id, system) {
        final raId = (system['ids'] as Map?)?['retroachievements'];
        if (raId != null && system['ra_hash'] == null) missing.add(id);
      });

      expect(missing, isEmpty);
    });

    test('a -hacks folder hashes the same way as its parent system', () {
      systems.forEach((id, system) {
        if (!id.endsWith('-hacks')) return;
        final parent = systems[id.substring(0, id.length - '-hacks'.length)];
        expect(parent, isNotNull, reason: 'no parent system for $id');
        expect(
          system['ra_hash']?['algo'],
          parent!['ra_hash']?['algo'],
          reason: '$id must hash like its parent platform',
        );
      });
    });

    test('only a disc system declares a disc algorithm', () {
      // A disc algorithm reads a filesystem inside the image. Pointed at a
      // cartridge folder it would find none and the system would match
      // nothing at all, which is a worse failure than the wrong algorithm.
      final discNames = RaHashAlgo.discJsonNames.toSet();
      systems.forEach((id, system) {
        final algo = system['ra_hash']?['algo'];
        if (algo == null || !discNames.contains(algo)) return;
        expect(
          system['multidisc'],
          isTrue,
          reason: '$id.json is not a disc system',
        );
        expect(
          (system['ids'] as Map?)?['retroachievements'],
          isNotNull,
          reason: '$id.json has no RetroAchievements console',
        );
      });
    });

    test('a system that reads inside its discs never guesses by filename', () {
      // Guessing is what attached partial sets and subsets to PlayStation
      // games (issue #8): a disc whose dump RetroAchievements has not
      // registered cannot earn anything, so naming it is worse than silence.
      final discNames = RaHashAlgo.discJsonNames.toSet();
      systems.forEach((id, system) {
        final algo = system['ra_hash']?['algo'];
        if (algo == null || !discNames.contains(algo)) return;
        expect(system['ra_hash']?['mode'], 'hash_only', reason: '$id mode');
      });
    });

    test('hack folders never guess by filename', () {
      // A hack is precisely the ROM RetroAchievements has not registered, so a
      // title guess there attaches a set the user can never earn.
      systems.forEach((id, system) {
        if (!id.endsWith('-hacks')) return;
        expect(system['ra_hash']?['mode'], 'hash_only', reason: '$id mode');
      });
    });
  });
}
