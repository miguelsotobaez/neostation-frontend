import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neostation/providers/neo_assets_provider.dart';
import 'package:neostation/services/neo_assets_service.dart';

/// A theme may only be recorded as applied once there is art to show for it.
///
/// The plan is built from the pack's declared `systems` list, so a dropped
/// metadata request covers nothing — and nothing is downloaded. Marking the
/// pack active anyway is how a theme comes to read as applied with not one
/// background on disk: no later launch re-plans it, so the user sees the pack
/// selected in System Art with plain backgrounds everywhere, and only re-picking
/// it by hand fixes that.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('neo_assets_apply_test');
  });

  tearDown(() {
    NeoAssetsService.debugReset();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  void useClient(Future<http.Response> Function(http.Request) handler) {
    NeoAssetsService.debugConfigure(
      client: MockClient(handler),
      cacheDir: tempDir.path,
    );
  }

  test('an unreachable theme manifest does not apply the pack', () async {
    useClient((_) async => http.Response('upstream is down', 503));

    final provider = NeoAssetsProvider();
    final applied = await provider.downloadAndApplyTheme('NeoStation', const [
      'gb',
      'snes',
    ]);

    expect(applied, isFalse);
    expect(provider.hasActiveTheme, isFalse);
    expect(provider.activeThemeFolder, isEmpty);
  });

  test(
    'a pack covering none of the installed systems does not apply',
    () async {
      useClient((request) async {
        if (request.url.path.endsWith('theme.json')) {
          return http.Response(
            jsonEncode({
              'version': '1.0.0',
              'systems': ['dreamcast'],
            }),
            200,
          );
        }
        return http.Response('not found', 404);
      });

      final provider = NeoAssetsProvider();
      final applied = await provider.downloadAndApplyTheme('NeoStation', const [
        'gb',
        'snes',
      ]);

      expect(applied, isFalse);
      expect(provider.hasActiveTheme, isFalse);
    },
  );
}
