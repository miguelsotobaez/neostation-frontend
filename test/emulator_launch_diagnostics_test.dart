import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/game/emulator_launch_diagnostics.dart';

/// Pins the behaviour that turns a silent launch failure into a readable one.
///
/// On a Steam Deck a failed launch and a finished game look identical: the
/// EmuDeck launcher script exits 0 either way, because it runs its own cleanup
/// after the emulator. The emulator's own output is the only witness, and it
/// used to be read into an empty callback and dropped.
void main() {
  group('describeExit', () {
    test('stays quiet when the emulator ran long enough to be played', () {
      final diagnostics = EmulatorLaunchDiagnostics('retroarch.sh')
        ..addLine('some chatter');

      expect(
        diagnostics.describeExit(0, const Duration(minutes: 12)),
        isNull,
        reason: 'a normal play session must not be reported as a failure',
      );
    });

    test('reports a launch that died instantly, even on exit code 0', () {
      // The exact shape of the arcade report: RetroArch rejected an incomplete
      // ROM set and gave up in about a second, but the launcher script's
      // trailing cleanup returned 0, so the app called it a finished session.
      final diagnostics = EmulatorLaunchDiagnostics('retroarch.sh')
        ..addLine('[libretro ERROR] [MAME 2003+] readroms failed')
        ..addLine('[ERROR] [Content] Failed to load content.');

      final report = diagnostics.describeExit(0, const Duration(seconds: 1));

      expect(report, isNotNull);
      expect(report, contains('readroms failed'));
      expect(report, contains('Failed to load content'));
      // The caveat matters as much as the lines: a reader who trusts the 0
      // stops looking exactly where the answer is.
      expect(report, contains('unreliable'));
    });

    test('says so explicitly when the emulator wrote nothing', () {
      final diagnostics = EmulatorLaunchDiagnostics('dolphin-emu.sh');

      final report = diagnostics.describeExit(1, const Duration(seconds: 2));

      expect(report, contains('wrote nothing'));
    });

    test('keeps the newest lines and discards the oldest', () {
      final diagnostics = EmulatorLaunchDiagnostics('retroarch.sh');
      for (var i = 0; i < EmulatorLaunchDiagnostics.maxCapturedLines + 5; i++) {
        diagnostics.addLine('line $i');
      }

      final report = diagnostics.describeExit(0, Duration.zero)!;

      // The error is always at the end, so the tail is the part worth keeping.
      expect(report, contains('line 16'));
      expect(report, isNot(contains('line 0')));
    });

    test('ignores blank output', () {
      final diagnostics = EmulatorLaunchDiagnostics('retroarch.sh')
        ..addLine('   ')
        ..addLine('');

      expect(
        diagnostics.describeExit(0, Duration.zero),
        contains('wrote nothing'),
      );
    });
  });

  group('formatCommand', () {
    test('quotes arguments containing spaces', () {
      // An unquoted ROM path silently becomes several arguments when pasted
      // back into a shell, which is how a copied command "works" differently
      // from the one that actually ran.
      final command = EmulatorLaunchDiagnostics.formatCommand('retroarch.sh', [
        '-L',
        '/cores/fbneo_libretro.so',
        '/roms/arcade/Some Game (USA).zip',
      ]);

      expect(
        command,
        'retroarch.sh -L /cores/fbneo_libretro.so '
        '"/roms/arcade/Some Game (USA).zip"',
      );
    });

    test('renders a command with no arguments', () {
      expect(
        EmulatorLaunchDiagnostics.formatCommand('/usr/bin/retroarch', const []),
        '/usr/bin/retroarch',
      );
    });
  });
}
