import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/log_redaction.dart';

void main() {
  group('redactSecrets — the observed leak', () {
    test('strips the RetroAchievements web API key from a request URI', () {
      // Verbatim shape of the line seen in app.log on the Thor: the key is in
      // the URI carried by an http ClientException, not in our own message.
      const line =
          'Error getting user profile: ClientException with SocketException: '
          'Failed host lookup, uri=https://retroachievements.org/API/'
          'API_GetUserProfile.php?u=SomeUser&y=9lUpeq4qAbNeIdtGlGk7D4Co9xPinq2O';

      final redacted = redactSecrets(line);

      expect(redacted, isNot(contains('9lUpeq4qAbNeIdtGlGk7D4Co9xPinq2O')));
      expect(redacted, contains('y=<redacted>'));
      // Everything needed to debug the failure survives.
      expect(redacted, contains('u=SomeUser'));
      expect(redacted, contains('API_GetUserProfile.php'));
      expect(redacted, contains('Failed host lookup'));
    });

    test('strips ScreenScraper developer and user credentials', () {
      const line =
          'GET https://api.screenscraper.fr/api2/jeuInfos.php?devid=neo'
          '&devpassword=s3cr3t&softname=NeoStation&ssid=someone'
          '&sspassword=hunter2&output=json';

      final redacted = redactSecrets(line);

      expect(redacted, isNot(contains('s3cr3t')));
      expect(redacted, isNot(contains('hunter2')));
      expect(redacted, isNot(contains('=neo&')));
      expect(redacted, contains('devpassword=<redacted>'));
      expect(redacted, contains('sspassword=<redacted>'));
      expect(redacted, contains('softname=NeoStation'));
      expect(redacted, contains('output=json'));
    });
  });

  group('redactSecrets — other credential shapes', () {
    test('redacts a bearer token', () {
      final redacted = redactSecrets(
        'headers: {Authorization: Bearer abc123DEF456ghi}',
      );
      expect(redacted, isNot(contains('abc123DEF456ghi')));
      expect(redacted, contains('Bearer <redacted>'));
    });

    test('redacts a JWT anywhere in the text', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
          '.eyJzdWIiOiIxMjM0NTY3ODkwIn0'
          '.dBjftJeZ4CVPmB92K27uhbUJU1p1r_wW1gFWFOEjXk';
      final redacted = redactSecrets('NeoSync session restored: $jwt');
      expect(redacted, isNot(contains('eyJhbGci')));
      expect(redacted, contains('<redacted>'));
      expect(redacted, contains('NeoSync session restored'));
    });

    test('redacts credentials embedded in a URL', () {
      final redacted = redactSecrets(
        'RomM: connecting to https://user:hunter2@romm.local/api/roms',
      );
      expect(redacted, isNot(contains('hunter2')));
      expect(redacted, contains('https://<redacted>@romm.local/api/roms'));
    });

    test('redacts credential-shaped JSON fields', () {
      final redacted = redactSecrets(
        'body: {"username": "someone", "password": "hunter2", '
        '"token": "abc.def"}',
      );
      expect(redacted, isNot(contains('hunter2')));
      expect(redacted, isNot(contains('abc.def')));
      expect(redacted, contains('someone'));
    });

    test('is case-insensitive about parameter names', () {
      final redacted = redactSecrets('?API_KEY=abc123&Password=xyz789');
      expect(redacted, isNot(contains('abc123')));
      expect(redacted, isNot(contains('xyz789')));
    });
  });

  group('redactSecrets — leaves ordinary logs alone', () {
    test('does not touch a normal message', () {
      const line = 'Database loaded: 35 systems with games';
      expect(redactSecrets(line), line);
    });

    test('does not touch a plain path or non-secret query', () {
      const line =
          'Scanning /storage/emulated/0/roms/nes — '
          'https://example.com/manifest.json?v=2&platform=android';
      expect(redactSecrets(line), line);
    });

    test('handles an empty string', () {
      expect(redactSecrets(''), '');
    });

    test('redaction is idempotent', () {
      const line = 'uri=https://retroachievements.org/API/x.php?u=me&y=SECRET';
      final once = redactSecrets(line);
      expect(redactSecrets(once), once);
    });
  });
}
