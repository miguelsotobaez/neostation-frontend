import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/desktop_window_focus.dart';

/// Pins the backstop that keeps a background NeoStation window from acting on
/// gamepad input.
///
/// Desktop gamepad input does not follow window focus, so an emulator running
/// in front of NeoStation still lets the pad reach the hidden UI. Any bug that
/// ends a game session early therefore turns into ghost navigation: presses
/// land on a window the user cannot see. These tests fix the two properties
/// that make the gate safe to have at all — it fails open, and it recovers.
void main() {
  setUp(DesktopWindowFocus.resetForTesting);
  tearDown(DesktopWindowFocus.resetForTesting);

  group('DesktopWindowFocus', () {
    test('allows input before initialization', () {
      // Fail open: Android and any platform that never reports focus must
      // behave exactly as they did before the gate existed.
      expect(DesktopWindowFocus.allowsInput, isTrue);
    });

    test('suppresses input while the window is blurred', () {
      DesktopWindowFocus.listenerForTesting.onWindowBlur();

      expect(DesktopWindowFocus.allowsInput, isFalse);
    });

    test('restores input when the window is focused again', () {
      DesktopWindowFocus.listenerForTesting
        ..onWindowBlur()
        ..onWindowFocus();

      expect(
        DesktopWindowFocus.allowsInput,
        isTrue,
        reason: 'returning from an emulator must hand the controller back',
      );
    });

    test('repeated blur and focus events are idempotent', () {
      final listener = DesktopWindowFocus.listenerForTesting;

      listener
        ..onWindowBlur()
        ..onWindowBlur();
      expect(DesktopWindowFocus.allowsInput, isFalse);

      listener
        ..onWindowFocus()
        ..onWindowFocus();
      expect(DesktopWindowFocus.allowsInput, isTrue);
    });

    test('verifySoon is inert when focus is not being tracked', () {
      // Nothing is listening in a unit test, so the corrective re-check must
      // not reach for a window-manager channel that does not exist.
      DesktopWindowFocus.setFocusedForTesting(false);

      expect(DesktopWindowFocus.verifySoon, returnsNormally);
      expect(DesktopWindowFocus.allowsInput, isFalse);
    });

    test('verifySoon does nothing while the window is already focused', () {
      expect(DesktopWindowFocus.verifySoon, returnsNormally);
      expect(DesktopWindowFocus.allowsInput, isTrue);
    });
  });
}
