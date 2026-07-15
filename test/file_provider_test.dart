import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/providers/file_provider.dart';

void main() {
  group('FileProvider.stripRomExtension', () {
    test('strips known common ROM extensions', () {
      expect(FileProvider.stripRomExtension('game.zip'), 'game');
      expect(FileProvider.stripRomExtension('Sonic.md'), 'Sonic');
      expect(FileProvider.stripRomExtension('Mega Man X4.chd'), 'Mega Man X4');
    });

    test('preserves version-like suffixes', () {
      expect(FileProvider.stripRomExtension('game.v1'), 'game.v1');
      expect(FileProvider.stripRomExtension('game.123'), 'game.123');
    });

    test('leaves names without an extension untouched', () {
      expect(FileProvider.stripRomExtension('noext'), 'noext');
    });

    test('strips against a system-specific extension whitelist', () {
      expect(FileProvider.stripRomExtension('game.zip', {'zip'}), 'game');
    });

    test('does not strip a long non-whitelisted suffix', () {
      // 'foobar' is 6 chars, not a common ROM ext, and not whitelisted.
      expect(
        FileProvider.stripRomExtension('game.foobar', {'zip'}),
        'game.foobar',
      );
    });
  });
}
