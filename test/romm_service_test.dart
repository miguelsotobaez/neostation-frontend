import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/romm_platform.dart';
import 'package:neostation/models/romm_rom.dart';
import 'package:neostation/services/romm_service.dart';

/// Builds a configured service. The HTTP client is a static final with no
/// injection seam, so these tests cover the deterministic (non-network) surface:
/// URL normalization/building and the image-auth-header guard.
RommService _service({
  String serverUrl = 'https://romm.local',
  String? accessToken,
}) {
  final s = RommService();
  s.configure(
    serverUrl: serverUrl,
    username: 'testuser',
    password: 's3cret',
    accessToken: accessToken,
  );
  return s;
}

RommRom _rom({
  String? urlCover,
  String? pathCoverLarge,
  String? pathCoverSmall,
}) => RommRom(
  id: 1,
  name: 'Game',
  platformId: 1,
  platformSlug: 'snes',
  fsName: 'game.sfc',
  fsNameNoExt: 'game',
  fsExtension: 'sfc',
  urlCover: urlCover,
  pathCoverLarge: pathCoverLarge,
  pathCoverSmall: pathCoverSmall,
);

RommPlatform _platform({String? urlLogo, String slug = 'snes'}) =>
    RommPlatform(id: 1, name: 'SNES', slug: slug, urlLogo: urlLogo);

void main() {
  group('configure / base URL normalization', () {
    test('prepends https:// when no scheme given', () {
      expect(_service(serverUrl: 'romm.local').baseUrl, 'https://romm.local');
    });

    test('preserves an explicit http:// scheme', () {
      expect(
        _service(serverUrl: 'http://192.168.1.10:8080').baseUrl,
        'http://192.168.1.10:8080',
      );
    });

    test('strips trailing slashes', () {
      expect(
        _service(serverUrl: 'https://romm.local/').baseUrl,
        'https://romm.local',
      );
      expect(
        _service(serverUrl: 'https://romm.local///').baseUrl,
        'https://romm.local',
      );
    });

    test('trims surrounding whitespace', () {
      expect(
        _service(serverUrl: '  https://romm.local  ').baseUrl,
        'https://romm.local',
      );
    });
  });

  group('coverUrl', () {
    test('returns null when ROM has no cover', () {
      expect(_service().coverUrl(_rom(urlCover: null)), isNull);
      expect(_service().coverUrl(_rom(urlCover: '')), isNull);
    });

    test('passes through an absolute URL unchanged', () {
      const abs = 'https://cdn.igdb/cover.png';
      expect(_service().coverUrl(_rom(urlCover: abs)), abs);
    });

    test('prefixes a server-relative path with the base URL', () {
      expect(
        _service().coverUrl(_rom(urlCover: '/assets/cover.png')),
        'https://romm.local/assets/cover.png',
      );
    });

    test('inserts a slash when the relative path lacks one', () {
      expect(
        _service().coverUrl(_rom(urlCover: 'assets/cover.png')),
        'https://romm.local/assets/cover.png',
      );
    });

    test(
      'falls back to RomM\'s cached cover when there is no provider URL',
      () {
        // The case behind the "no art in the browser, but the download has it"
        // report: RomM cached a cover file but recorded no url_cover.
        expect(
          _service().coverUrl(
            _rom(
              pathCoverLarge: '/assets/romm/resources/roms/1/2/cover/big.png',
            ),
          ),
          'https://romm.local/assets/romm/resources/roms/1/2/cover/big.png',
        );
      },
    );
  });

  group('coverUrlCandidates', () {
    test('orders provider URL, then cached large, then cached small', () {
      final urls = _service().coverUrlCandidates(
        _rom(
          urlCover: 'https://cdn.igdb/cover.png',
          pathCoverLarge: '/assets/big.png',
          pathCoverSmall: '/assets/small.png',
        ),
      );
      expect(urls, [
        'https://cdn.igdb/cover.png',
        'https://romm.local/assets/big.png',
        'https://romm.local/assets/small.png',
      ]);
    });

    test('skips sources the server left empty', () {
      final urls = _service().coverUrlCandidates(
        _rom(urlCover: '', pathCoverLarge: '', pathCoverSmall: '/assets/s.png'),
      );
      expect(urls, ['https://romm.local/assets/s.png']);
    });

    test('is empty when the ROM has no cover at all', () {
      expect(_service().coverUrlCandidates(_rom()), isEmpty);
    });
  });

  group('platformLogoUrl', () {
    test('returns null when no logo', () {
      expect(_service().platformLogoUrl(_platform(urlLogo: null)), isNull);
    });

    test('passes through absolute IGDB CDN URLs', () {
      const abs = 'https://images.igdb.com/logo.png';
      expect(_service().platformLogoUrl(_platform(urlLogo: abs)), abs);
    });

    test('prefixes relative logos with the base URL', () {
      expect(
        _service().platformLogoUrl(_platform(urlLogo: 'media/logo.png')),
        'https://romm.local/media/logo.png',
      );
    });
  });

  group('platformIconUrl', () {
    test('builds the bundled SVG path from the slug', () {
      expect(
        _service().platformIconUrl(_platform(slug: 'gba')),
        'https://romm.local/assets/platforms/gba.svg',
      );
    });
  });

  group('imageHeadersFor (token-leak guard)', () {
    test('sends the bearer token for same-server URLs', () {
      final s = _service(accessToken: 'tok-123');
      final headers = s.imageHeadersFor('https://romm.local/assets/x.png');
      expect(headers['Authorization'], 'Bearer tok-123');
    });

    test('never leaks the token to third-party CDN URLs', () {
      final s = _service(accessToken: 'tok-123');
      expect(s.imageHeadersFor('https://images.igdb.com/x.png'), isEmpty);
    });

    test('sends no auth header when there is no access token', () {
      final s = _service(accessToken: null);
      expect(s.imageHeadersFor('https://romm.local/assets/x.png'), isEmpty);
    });
  });

  group('imageExtensionFor (magic numbers)', () {
    test('detects JPEG', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0x00, 0x01]);
      expect(RommService.imageExtensionFor(jpeg), 'jpg');
    });

    test('detects WEBP via the RIFF/WEBP header', () {
      // bytes[8..11] must spell "WEBP".
      final webp = Uint8List.fromList([
        0x52, 0x49, 0x46, 0x46, // RIFF
        0x00, 0x00, 0x00, 0x00, // size
        0x57, 0x45, 0x42, 0x50, // WEBP
      ]);
      expect(RommService.imageExtensionFor(webp), 'webp');
    });

    test('defaults to png for unrecognized/short data', () {
      expect(
        RommService.imageExtensionFor(Uint8List.fromList([0x89, 0x50])),
        'png',
      );
      expect(RommService.imageExtensionFor(Uint8List(0)), 'png');
    });
  });

  group('parseRaProgression', () {
    test('maps rom_ra_id to num_awarded', () {
      const body = '''
        {"username":"testuser","ra_username":"testuser",
         "ra_progression":{"total":2,"results":[
           {"rom_ra_id":14402,"num_awarded":5,"max_possible":30},
           {"rom_ra_id":777,"num_awarded":0,"max_possible":12}
         ]}}''';
      final map = RommService.parseRaProgression(body);
      expect(map[14402], 5);
      expect(map[777], 0);
      expect(map.length, 2);
    });

    test('returns empty map when no ra_progression', () {
      expect(
        RommService.parseRaProgression('{"username":"testuser"}'),
        isEmpty,
      );
      expect(
        RommService.parseRaProgression('{"ra_progression":null}'),
        isEmpty,
      );
    });

    test('skips entries missing rom_ra_id or num_awarded', () {
      const body = '''
        {"ra_progression":{"results":[
          {"num_awarded":5},
          {"rom_ra_id":1},
          {"rom_ra_id":2,"num_awarded":3}
        ]}}''';
      final map = RommService.parseRaProgression(body);
      expect(map, {2: 3});
    });

    test('tolerates a non-object / non-list payload', () {
      expect(RommService.parseRaProgression('[]'), isEmpty);
      expect(
        RommService.parseRaProgression('{"ra_progression":{"results":{}}}'),
        isEmpty,
      );
    });
  });

  group('RommException', () {
    test('toString includes status code and message', () {
      final e = RommException('Invalid credentials', statusCode: 401);
      expect(e.toString(), 'RommException(401): Invalid credentials');
      expect(e.message, 'Invalid credentials');
      expect(e.statusCode, 401);
    });
  });
}
