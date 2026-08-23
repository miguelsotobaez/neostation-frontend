import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/logger_service.dart';

/// Tests for the log capture a background isolate uses to hand its diagnostics
/// back to the isolate that owns the log file.
///
/// `compute()` spawns an isolate with its own copy of the [LoggerService]
/// singleton, and that copy never runs [LoggerService.init] — two isolates
/// holding a `FileOutput` on one path would interleave writes and race the
/// rotation rename. So everything the RetroAchievements disc reader logs about
/// a failed hash went to the console only, and the `app.log` a user sends kept
/// no trace of it beyond the pass's own skip count.
void main() {
  final log = LoggerService.instance;

  tearDown(() {
    // A capture left running would follow this singleton into the next test.
    log.takeCapture();
  });

  group('capturing', () {
    test('collects nothing until asked', () {
      log.w('before any capture');

      expect(log.takeCapture(), isEmpty);
    });

    test('collects a line per level, tagged with its severity', () {
      log.startCapture();
      log.i('info line');
      log.w('warning line');
      log.e('error line');
      log.d('debug line');

      expect(log.takeCapture(), [
        'i|info line',
        'w|warning line',
        'e|error line',
        'd|debug line',
      ]);
    });

    test('keeps the error object, which is where the reason usually is', () {
      log.startCapture();
      log.e('CHD: failed to open', error: 'PathNotFoundException');

      expect(log.takeCapture(), [
        'e|CHD: failed to open PathNotFoundException',
      ]);
    });

    test('stops collecting once taken', () {
      log.startCapture();
      log.w('first');
      log.takeCapture();

      log.w('second');

      expect(log.takeCapture(), isEmpty);
    });

    test('bounds what one capture holds', () {
      // A capture explains a single failure. An unbounded list in a background
      // isolate is a leak waiting for a pathological image.
      log.startCapture();
      for (var i = 0; i < 200; i++) {
        log.w('line $i');
      }

      final captured = log.takeCapture();

      expect(captured, hasLength(64));
      expect(captured.first, 'w|line 0');
      expect(captured.last, 'w|line 63');
    });
  });

  group('replaying', () {
    test('re-logs each line at the level it was captured at', () {
      // Replaying goes back through log(), so capturing around it shows what
      // the file output would have received.
      log.startCapture();
      log.replayCaptured([
        'w|RA disc: could not open game.chd',
        'e|CHD: no file descriptor',
        'i|RA disc: SLUS_202.02 has no PS-X EXE marker',
      ]);

      expect(log.takeCapture(), [
        'w|RA disc: could not open game.chd',
        'e|CHD: no file descriptor',
        'i|RA disc: SLUS_202.02 has no PS-X EXE marker',
      ]);
    });

    test('survives a line that carries no level tag', () {
      log.startCapture();
      log.replayCaptured(['', 'x', 'no separator here', 'w|kept']);

      expect(log.takeCapture(), ['w|kept']);
    });

    test('treats an unknown tag as info rather than dropping the line', () {
      log.startCapture();
      log.replayCaptured(['?|from a newer build']);

      expect(log.takeCapture(), ['i|from a newer build']);
    });
  });
}
