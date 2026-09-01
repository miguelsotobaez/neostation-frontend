import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/archive_service.dart';
import 'package:path/path.dart' as path;

/// Entry names are attacker-controlled data inside the archive, so the guard
/// has to hold for shapes no honest ROM set ever produces.
void main() {
  const tempDir = '/data/user-data/temp/snes/Chrono Trigger.zip';

  group('ArchiveService.safeOutputPath', () {
    test('an ordinary entry lands inside the temp directory', () {
      final resolved = ArchiveService.safeOutputPath(
        tempDir,
        'Chrono Trigger.sfc',
      );

      expect(resolved, isNotNull);
      expect(path.isWithin(tempDir, resolved!), isTrue);
    });

    test('a nested entry is allowed — archives legitimately hold folders', () {
      final resolved = ArchiveService.safeOutputPath(
        tempDir,
        'disc1/Game (Track 01).bin',
      );

      expect(resolved, isNotNull);
      expect(path.isWithin(tempDir, resolved!), isTrue);
    });

    test('a "./" prefix is not mistaken for an escape', () {
      expect(ArchiveService.safeOutputPath(tempDir, './Game.sfc'), isNotNull);
    });

    test('a ../ traversal is refused', () {
      expect(ArchiveService.safeOutputPath(tempDir, '../escaped.sfc'), isNull);
    });

    test('a deep traversal out of user-data is refused', () {
      expect(
        ArchiveService.safeOutputPath(tempDir, '../../../../../../etc/passwd'),
        isNull,
      );
    });

    test('an absolute entry name is refused', () {
      // The quiet one: path.join treats an absolute second argument as the
      // whole path and drops the temp directory without complaint, so this
      // escapes without needing a single "..".
      expect(
        path.join(tempDir, '/etc/cron.d/payload'),
        '/etc/cron.d/payload',
        reason: 'documents the path.join behaviour the guard exists for',
      );

      expect(
        ArchiveService.safeOutputPath(tempDir, '/etc/cron.d/payload'),
        isNull,
      );
    });

    test('a traversal that resolves back inside is still allowed', () {
      // Not an escape: it ends up under the root, so refusing it would be a
      // false positive on an archive that merely names its entries oddly.
      expect(
        ArchiveService.safeOutputPath(tempDir, 'sub/../Game.sfc'),
        isNotNull,
      );
    });

    test('an entry naming the directory itself is refused', () {
      expect(ArchiveService.safeOutputPath(tempDir, '.'), isNull);
      expect(ArchiveService.safeOutputPath(tempDir, ''), isNull);
    });
  });
}
