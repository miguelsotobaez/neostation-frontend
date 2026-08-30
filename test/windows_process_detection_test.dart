import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/game/game_launch_service.dart';

/// Pins the parsing of `tasklist` output that decides whether a launched
/// emulator is still alive on Windows.
///
/// The desktop session poll asks this question every two seconds; a false "not
/// running" ends the session while the game is still on screen, which closes
/// the launch dialog and reactivates gamepad navigation behind the emulator.
/// The reported symptom was NeoStation navigating and launching further games
/// under a running DuckStation.
void main() {
  group('csvListsProcess', () {
    test('matches an image name too long for the default table column', () {
      // The exact failure: tasklist's table format caps the image-name column
      // at 25 characters, so `duckstation-qt-x64-ReleaseLTCG.exe` printed as
      // `duckstation-qt-x64-Releas` and never matched. CSV quotes it in full.
      const output =
          '"duckstation-qt-x64-ReleaseLTCG.exe","4692","Console","1","301,984 K"';

      expect(
        GameLaunchService.csvListsProcess(
          output,
          'duckstation-qt-x64-ReleaseLTCG.exe',
        ),
        isTrue,
        reason: 'a running emulator must never be reported as exited',
      );
    });

    test('matches a short image name', () {
      const output = '"retroarch.exe","1234","Console","1","120,000 K"';

      expect(
        GameLaunchService.csvListsProcess(output, 'retroarch.exe'),
        isTrue,
      );
    });

    test('ignores case, as Windows does', () {
      const output = '"RetroArch.exe","1234","Console","1","120,000 K"';

      expect(
        GameLaunchService.csvListsProcess(output, 'retroarch.exe'),
        isTrue,
      );
    });

    test('reports nothing running when the filter selected nothing', () {
      const output =
          'INFO: No tasks are running which match the specified criteria.';

      expect(
        GameLaunchService.csvListsProcess(output, 'duckstation.exe'),
        isFalse,
      );
    });

    test('reports nothing running for empty output', () {
      expect(GameLaunchService.csvListsProcess('', 'duckstation.exe'), isFalse);
    });

    test('does not match a different process', () {
      const output = '"retroarch.exe","1234","Console","1","120,000 K"';

      expect(
        GameLaunchService.csvListsProcess(output, 'duckstation.exe'),
        isFalse,
      );
    });

    test('does not match the name appearing in a later column', () {
      // Defensive: only the image-name field decides. A name that turns up
      // anywhere else in the row is not this process running.
      const output = '"other.exe","1234","duckstation.exe","1","120,000 K"';

      expect(
        GameLaunchService.csvListsProcess(output, 'duckstation.exe'),
        isFalse,
      );
    });

    test('does not match on a shared prefix', () {
      const output =
          '"duckstation-qt-x64-ReleaseLTCG.exe","4692","Console","1","301,984 K"';

      expect(
        GameLaunchService.csvListsProcess(output, 'duckstation.exe'),
        isFalse,
      );
    });

    test('finds the process among several rows', () {
      const output =
          '"retroarch.exe","1234","Console","1","120,000 K"\r\n'
          '"duckstation-qt-x64-ReleaseLTCG.exe","4692","Console","1","301,984 K"\r\n';

      expect(
        GameLaunchService.csvListsProcess(
          output,
          'duckstation-qt-x64-ReleaseLTCG.exe',
        ),
        isTrue,
      );
    });
  });
}
