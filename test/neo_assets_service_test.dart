import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neostation/services/neo_assets_service.dart';
import 'package:path/path.dart' as path;

/// Coverage comes from the theme's declared `systems` list, so a system the
/// pack does not cover is never requested at all. What still has to hold is
/// the split between "the server says this is absent" (404) and "the server
/// could not be reached" (timeout, 429, 5xx): only the former is a fact about
/// the pack, and treating the latter as absence is how systems used to lose
/// their backgrounds for the life of an install.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('neo_assets_test');
  });

  tearDown(() {
    NeoAssetsService.debugReset();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  /// Wires the service to [handler] and a scratch cache directory.
  void useClient(Future<http.Response> Function(http.Request) handler) {
    NeoAssetsService.debugConfigure(
      client: MockClient(handler),
      cacheDir: tempDir.path,
    );
  }

  File backgroundFile(String theme, String system, {String ext = 'webp'}) =>
      File(path.join(tempDir.path, theme, 'backgrounds', '$system.$ext'));

  group('getCachedBackground', () {
    test('caches the webp when the asset exists', () async {
      useClient((request) async {
        if (request.url.path.endsWith('/backgrounds/wii.webp')) {
          return http.Response.bytes([1, 2, 3], 200);
        }
        return http.Response('not found', 404);
      });

      final result = await NeoAssetsService.getCachedBackground(
        'NeoStation',
        'wii',
      );

      expect(result, isNotNull);
      expect(File(result!).readAsBytesSync(), [1, 2, 3]);
    });

    test('leaves no .part file behind on success', () async {
      useClient((request) async => http.Response.bytes([1], 200));

      await NeoAssetsService.getCachedBackground('NeoStation', 'wii');

      final parts = Directory(
        path.join(tempDir.path, 'NeoStation'),
      ).listSync(recursive: true).where((e) => e.path.endsWith('.part'));
      expect(parts, isEmpty);
    });

    test('falls back to the legacy gif when the webp is a 404', () async {
      useClient((request) async {
        if (request.url.path.endsWith('.gif')) {
          return http.Response.bytes([7], 200);
        }
        return http.Response('not found', 404);
      });

      final result = await NeoAssetsService.getCachedBackground(
        'NeoStation',
        'wii',
      );

      expect(result, isNotNull);
      expect(
        backgroundFile('NeoStation', 'wii', ext: 'gif').existsSync(),
        true,
      );
    });

    test('a rate-limited webp does not go on to probe the gif', () async {
      // A server refusing requests has nothing to say about the legacy gif
      // either, and probing it would double the wait across ~100 systems.
      final requested = <String>[];
      useClient((request) async {
        requested.add(request.url.path);
        return http.Response('rate limited', 429);
      });

      final result = await NeoAssetsService.getCachedBackground(
        'NeoStation',
        'pce',
      );

      expect(result, isNull);
      expect(requested.length, 3);
      expect(requested.every((p) => p.endsWith('.webp')), isTrue);
    });

    test('a network error leaves nothing cached', () async {
      useClient((request) async => throw const SocketException('reset'));

      final result = await NeoAssetsService.getCachedBackground(
        'NeoStation',
        'pccd',
      );

      expect(result, isNull);
      expect(backgroundFile('NeoStation', 'pccd').existsSync(), isFalse);
    });

    test('a transient failure resolves on a later attempt', () async {
      var attempts = 0;
      useClient((request) async {
        attempts++;
        if (attempts == 1) return http.Response('rate limited', 429);
        return http.Response.bytes([9], 200);
      });

      final result = await NeoAssetsService.getCachedBackground(
        'NeoStation',
        'wii',
      );

      expect(result, isNotNull);
    });
  });

  group('buildThemeDownloadPlan coverage', () {
    /// Serves a theme.json declaring [systems], and 404s every asset.
    void serveMetadata(List<String>? systems) {
      useClient((request) async {
        if (request.url.path.endsWith('theme.json')) {
          return http.Response(
            jsonEncode({'version': '1.0.0', 'systems': ?systems}),
            200,
          );
        }
        return http.Response('not found', 404);
      });
    }

    test('plans only the systems the theme declares', () async {
      serveMetadata(['wii', 'snes']);

      final plan = await NeoAssetsService.buildThemeDownloadPlan('NeoStation', [
        'wii',
        'snes',
        'uncovered',
      ]);

      expect(plan.systemsToDownload, ['wii', 'snes']);
    });

    test('covers nothing when no systems list is declared', () async {
      // Blind-probing every system is what the old negative cache existed to
      // prevent, so an undeclared list must not fall back to "all systems".
      serveMetadata(null);

      final plan = await NeoAssetsService.buildThemeDownloadPlan('NeoStation', [
        'wii',
        'snes',
      ]);

      expect(plan.systemsToDownload, isEmpty);
      expect(plan.totalAssetsToDownload, 0);
    });

    test('falls back to the cached theme.json when offline', () async {
      final metadata = File(
        path.join(tempDir.path, 'NeoStation', 'theme.json'),
      );
      metadata.parent.createSync(recursive: true);
      metadata.writeAsStringSync(
        jsonEncode({
          'version': '1.0.0',
          'systems': ['wii'],
        }),
      );

      useClient((request) async => throw const SocketException('offline'));

      final plan = await NeoAssetsService.buildThemeDownloadPlan('NeoStation', [
        'wii',
        'snes',
      ]);

      expect(plan.systemsToDownload, ['wii']);
    });
  });

  group('deleteLegacyMissingMarkers', () {
    test('clears markers once, then does not walk the cache again', () async {
      NeoAssetsService.debugConfigure(cacheDir: tempDir.path);

      final marker = File(
        path.join(tempDir.path, 'NeoStation', 'backgrounds', 'wii.missing'),
      );
      marker.parent.createSync(recursive: true);
      marker.writeAsStringSync('');

      await NeoAssetsService.deleteLegacyMissingMarkers();
      expect(marker.existsSync(), isFalse);

      // The sentinel makes this a one-shot sweep, so a file recreated
      // afterwards is left alone rather than costing a walk on every plan.
      marker.writeAsStringSync('');
      await NeoAssetsService.deleteLegacyMissingMarkers();
      expect(marker.existsSync(), isTrue);
    });
  });
}
