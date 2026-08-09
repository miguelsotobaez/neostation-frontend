import 'dart:convert';
import 'dart:io';

import 'package:neostation/services/logger_service.dart';

/// Records what a launched emulator was told to do and what it said back, so a
/// failed launch can explain itself.
///
/// Two things conspire to make a Linux launch failure invisible. The launch
/// path drained the emulator's stdout and stderr into empty callbacks, throwing
/// away the only account of what went wrong; and on a Steam Deck the exit code
/// is not the emulator's at all — EmuDeck's launcher scripts run their own
/// cleanup after the emulator returns, so the script reports *that* command's
/// status. A RetroArch that rejected its ROM and a RetroArch the user quit both
/// arrive as "exited with code 0", instantly, with no other trace.
///
/// Diagnosing one such report meant reconstructing the command by hand and
/// re-running it on the device. Everything needed was in the emulator's output,
/// already being read and discarded.
class EmulatorLaunchDiagnostics {
  static final _log = LoggerService.instance;

  /// How many of the emulator's most recent output lines to keep.
  ///
  /// The interesting part of a failure is the end — the error and whatever
  /// context immediately preceded it. Emulators are verbose enough that
  /// retaining more would push a real log into the noise.
  static const int maxCapturedLines = 12;

  /// Below this, an exit is treated as a failed launch rather than a session.
  ///
  /// Nobody starts a game and quits within a few seconds, whereas every failure
  /// mode seen so far — a missing libretro core, an incomplete ROM set — gives
  /// up in about a second.
  static const Duration suspiciouslyFast = Duration(seconds: 10);

  final String executable;
  final Stopwatch _elapsed;
  final List<String> _tail = [];

  EmulatorLaunchDiagnostics(this.executable, {Stopwatch? elapsed})
    : _elapsed = elapsed ?? (Stopwatch()..start());

  /// Logs the resolved command and starts capturing [process]'s output.
  ///
  /// The command is logged in full because it is the thing no one can
  /// reconstruct afterwards: by this point the executable has been through
  /// discovery and the arguments through core-absolutisation, so neither
  /// matches what the systems JSON says.
  static EmulatorLaunchDiagnostics attach(
    Process process,
    String executable,
    List<String> args,
  ) {
    _log.i('Launching: ${formatCommand(executable, args)}');
    final diagnostics = EmulatorLaunchDiagnostics(executable);
    diagnostics._capture(process.stdout);
    diagnostics._capture(process.stderr);
    return diagnostics;
  }

  void _capture(Stream<List<int>> stream) {
    stream
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen(addLine, onError: (_) {});
  }

  /// Retains [line], dropping the oldest once [maxCapturedLines] is reached.
  void addLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    _tail.add(trimmed);
    if (_tail.length > maxCapturedLines) _tail.removeAt(0);
  }

  /// Logs why the launch looks failed, or stays quiet when it looks like a
  /// normal play session.
  void reportExit(int exitCode) {
    final report = describeExit(exitCode, _elapsed.elapsed);
    if (report != null) _log.w(report);
  }

  /// Returns the diagnostic for an emulator that exited after [elapsed], or
  /// `null` when the exit looks like an ordinary end to a play session.
  String? describeExit(int exitCode, Duration elapsed) {
    if (elapsed >= suspiciouslyFast) return null;

    final report = StringBuffer()
      ..writeln(
        '$executable exited after ${elapsed.inMilliseconds}ms with code '
        '$exitCode — too fast to be a play session, so the launch most likely '
        'failed.',
      )
      ..writeln(
        'Treat the code as unreliable: an EmuDeck launcher script runs its own '
        'cleanup after the emulator, so it reports that cleanup\'s status '
        'rather than the emulator\'s.',
      );

    if (_tail.isEmpty) {
      report.write('The emulator wrote nothing before exiting.');
    } else {
      report.writeln('Last ${_tail.length} line(s) from the emulator:');
      report.write(_tail.map((line) => '  $line').join('\n'));
    }
    return report.toString();
  }

  /// Renders a command in a form that can be pasted into a shell.
  ///
  /// ROM paths routinely contain spaces, and an unquoted one turns a copied
  /// command into a different, working-by-accident command — or a broken one.
  static String formatCommand(String executable, List<String> args) {
    return [
      executable,
      ...args,
    ].map((part) => part.contains(' ') ? '"$part"' : part).join(' ');
  }
}
