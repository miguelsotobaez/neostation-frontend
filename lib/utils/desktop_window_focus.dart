import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import 'package:neostation/services/logger_service.dart';

/// Tracks whether the NeoStation window currently holds OS focus on desktop.
///
/// Desktop gamepad input does not follow window focus the way keyboard input
/// does: the backend reads the device directly, so a launched emulator sitting
/// in front of NeoStation does not stop the pad from reaching us. The only
/// thing that normally keeps the hidden UI quiet during a game is the launch
/// flow deactivating its navigation layers — which means any bug that ends a
/// session early (see the tasklist image-name truncation fixed alongside this)
/// hands the controller straight back to a window the user cannot see, and
/// their next few presses navigate and launch games behind the emulator.
///
/// This is the backstop for that whole class of bug: while the window is
/// blurred, gamepad input is not acted on regardless of what the session
/// bookkeeping believes.
///
/// **Fail open.** The flag starts `true` and every uncertain path leaves it
/// `true`, so a platform that never reports focus at all behaves exactly as it
/// does today. The dangerous direction is a *missed focus* event stranding the
/// app as permanently blurred, so [verifySoon] re-asks the window manager
/// (at most once a second) whenever input arrives while we believe we are
/// blurred. A missed event then costs one press, not the session.
///
/// Android is untouched: it blocks the pad natively while an emulator is in
/// the foreground, and [initialize] is never called there.
class DesktopWindowFocus with WindowListener {
  DesktopWindowFocus._();

  static final DesktopWindowFocus _instance = DesktopWindowFocus._();

  static final _log = LoggerService.instance;

  /// Minimum spacing between the corrective [verifySoon] round-trips, so a held
  /// direction cannot fire one per event.
  static const Duration _verifyInterval = Duration(seconds: 1);

  static bool _focused = true;
  static bool _listening = false;
  static DateTime? _lastVerification;

  /// Whether gamepad input should be acted on right now.
  ///
  /// Always true off desktop and before [initialize] has run.
  static bool get allowsInput => _focused;

  /// Starts tracking window focus. Desktop only; safe to call more than once.
  ///
  /// Call after `windowManager.ensureInitialized()`, which owns the channel
  /// this listens on.
  static Future<void> initialize() async {
    if (!Platform.isWindows && !Platform.isLinux && !Platform.isMacOS) return;
    if (_listening) return;

    windowManager.addListener(_instance);
    _listening = true;

    // Seed from the real state rather than assuming: initialization happens
    // during startup, and the user may already have clicked away.
    try {
      _focused = await windowManager.isFocused();
    } catch (e) {
      // Leave the fail-open default in place.
      _log.w('[WindowFocus] Could not read initial focus state: $e');
    }

    _log.i('[WindowFocus] Tracking window focus (focused: $_focused)');
  }

  /// Re-checks the real focus state, at most once per [_verifyInterval].
  ///
  /// The corrective path for a focus event that never arrived. Deliberately
  /// fire-and-forget: the event that triggered it is still dropped, and the
  /// answer lands in time for the next one.
  static void verifySoon() {
    if (!_listening || _focused) return;

    final now = DateTime.now();
    if (_lastVerification != null &&
        now.difference(_lastVerification!) < _verifyInterval) {
      return;
    }
    _lastVerification = now;

    windowManager
        .isFocused()
        .then((focused) {
          if (focused && !_focused) {
            _log.w(
              '[WindowFocus] Input arrived while blurred but the window is '
              'focused; correcting (a focus event was missed)',
            );
            _focused = true;
          }
        })
        .catchError((Object e) {
          _log.w('[WindowFocus] Focus re-check failed: $e');
        });
  }

  @override
  void onWindowFocus() {
    if (_focused) return;
    _focused = true;
    _log.i('[WindowFocus] Window focused — gamepad input enabled');
  }

  @override
  void onWindowBlur() {
    if (!_focused) return;
    _focused = false;
    _log.i('[WindowFocus] Window blurred — gamepad input suppressed');
  }

  /// Overrides the tracked state. Tests only.
  @visibleForTesting
  static void setFocusedForTesting(bool focused) => _focused = focused;

  /// Restores the pristine state. Tests only.
  @visibleForTesting
  static void resetForTesting() {
    _focused = true;
    _listening = false;
    _lastVerification = null;
  }

  /// Drives [onWindowFocus]/[onWindowBlur] without a real window. Tests only.
  @visibleForTesting
  static DesktopWindowFocus get listenerForTesting => _instance;
}
