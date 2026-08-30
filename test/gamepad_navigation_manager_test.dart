import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';

/// Records which layer the manager considers active, in push/activation order.
class _Recorder {
  final List<String> events = [];

  void push(String id, {bool modal = false}) {
    GamepadNavigationManager.pushLayer(
      id,
      onActivate: () => events.add('+$id'),
      onDeactivate: () => events.add('-$id'),
      modal: modal,
    );
  }

  void pop(String id) => GamepadNavigationManager.popLayer(id);
}

void main() {
  group('GamepadNavigationManager modal layers', () {
    test('a non-modal push does not steal focus from an open modal', () {
      final r = _Recorder();
      r.push('app_screen');
      r.push('systems_update_dialog', modal: true);
      r.events.clear();

      // The systems grid mounts when the startup scan finishes, behind the
      // dialog. It must not take the controller.
      r.push('my_systems_list');

      expect(r.events, isEmpty);

      r.pop('my_systems_list');
      r.pop('systems_update_dialog');
      r.pop('app_screen');
    });

    test(
      'the layer pushed under a modal becomes active once it is dismissed',
      () {
        final r = _Recorder();
        r.push('app_screen');
        r.push('systems_update_dialog', modal: true);
        r.push('my_systems_list');
        r.events.clear();

        r.pop('systems_update_dialog');

        expect(r.events, ['-systems_update_dialog', '+my_systems_list']);

        r.pop('my_systems_list');
        r.pop('app_screen');
      },
    );

    test('a modal still stacks on top of another modal', () {
      final r = _Recorder();
      r.push('app_screen');
      r.push('update_dialog', modal: true);
      r.events.clear();

      r.push('systems_update_dialog', modal: true);

      expect(r.events, ['-update_dialog', '+systems_update_dialog']);

      r.pop('systems_update_dialog');
      r.pop('update_dialog');
      r.pop('app_screen');
    });

    test(
      'non-modal pushes slot below the lowest modal, keeping dialog order',
      () {
        final r = _Recorder();
        r.push('app_screen');
        r.push('update_dialog', modal: true);
        r.push('systems_update_dialog', modal: true);
        r.push('my_systems_list');
        r.events.clear();

        // Dismissing the top dialog must return focus to the one underneath it,
        // not to the background layer that mounted late.
        r.pop('systems_update_dialog');
        expect(r.events, ['-systems_update_dialog', '+update_dialog']);

        r.events.clear();
        r.pop('update_dialog');
        expect(r.events, ['-update_dialog', '+my_systems_list']);

        r.pop('my_systems_list');
        r.pop('app_screen');
      },
    );

    test('ordinary stacking is unchanged when no modal is open', () {
      final r = _Recorder();
      r.push('app_screen');
      r.events.clear();

      r.push('my_systems_list');
      expect(r.events, ['-app_screen', '+my_systems_list']);

      r.events.clear();
      r.pop('my_systems_list');
      expect(r.events, ['-my_systems_list', '+app_screen']);

      r.pop('app_screen');
    });
  });

  group('GamepadNavigationManager launch focus owner', () {
    test(
      'returns input to the launching screen, not to whatever drifted up',
      () {
        // The observed failure: launching frees memory and clears artwork
        // caches, the systems carousel remounts behind the launch dialog and
        // re-pushes its layer, and the games list the user is looking at ends up
        // buried. Waking "the top layer" then woke the carousel and the
        // controller looked dead.
        final r = _Recorder();
        r.push('app_screen');
        r.push('my_systems_list');
        r.push('system_games_list');

        GamepadNavigationManager.rememberFocusOwner('system_games_list');
        GamepadNavigationManager.deactivateAll();

        // The background screen remounts mid-launch and lands on top.
        r.pop('my_systems_list');
        r.push('my_systems_list');
        r.events.clear();

        GamepadNavigationManager.restoreFocusOwner();

        expect(r.events, ['-my_systems_list', '+system_games_list']);

        r.pop('system_games_list');
        r.pop('my_systems_list');
        r.pop('app_screen');
      },
    );

    test('leaves the owner alone when it is already on top', () {
      final r = _Recorder();
      r.push('app_screen');
      r.push('system_games_list');

      GamepadNavigationManager.rememberFocusOwner('system_games_list');
      GamepadNavigationManager.deactivateAll();
      r.events.clear();

      GamepadNavigationManager.restoreFocusOwner();

      expect(r.events, [
        '+system_games_list',
      ], reason: 'the ordinary path must not churn the stack');

      r.pop('system_games_list');
      r.pop('app_screen');
    });

    test('falls back to the top layer when the owner is gone', () {
      // Its screen was disposed while the game ran.
      final r = _Recorder();
      r.push('app_screen');
      r.push('system_games_list');

      GamepadNavigationManager.rememberFocusOwner('system_games_list');
      GamepadNavigationManager.deactivateAll();
      r.pop('system_games_list');
      r.events.clear();

      GamepadNavigationManager.restoreFocusOwner();

      expect(r.events, ['+app_screen']);

      r.pop('app_screen');
    });

    test('falls back to the top layer when no owner was remembered', () {
      final r = _Recorder();
      r.push('app_screen');
      r.push('my_systems_list');
      GamepadNavigationManager.deactivateAll();
      r.events.clear();

      GamepadNavigationManager.restoreFocusOwner();

      expect(r.events, ['+my_systems_list']);

      r.pop('my_systems_list');
      r.pop('app_screen');
    });

    test('a remembered owner is consumed, not reused by the next launch', () {
      final r = _Recorder();
      r.push('app_screen');
      r.push('system_games_list');

      GamepadNavigationManager.rememberFocusOwner('system_games_list');
      GamepadNavigationManager.restoreFocusOwner();

      // A later layer opens with nothing remembered for it. A stale owner
      // would drag input back to the games list underneath.
      r.push('game_settings_dialog');
      r.events.clear();

      GamepadNavigationManager.restoreFocusOwner();

      expect(r.events, ['+game_settings_dialog']);

      r.pop('game_settings_dialog');
      r.pop('system_games_list');
      r.pop('app_screen');
    });

    test('the modal launch dialog keeps input while a screen remounts', () {
      // The dialog owns A/B (dismiss) for its whole lifetime; a background
      // remount used to take that off it.
      final r = _Recorder();
      r.push('app_screen');
      r.push('system_games_list');
      r.push('game_launch_dialog', modal: true);
      r.events.clear();

      r.pop('my_systems_list'); // Not registered; mirrors a real remount.
      r.push('my_systems_list');

      expect(r.events, isEmpty);

      r.pop('game_launch_dialog');
      r.pop('my_systems_list');
      r.pop('system_games_list');
      r.pop('app_screen');
    });
  });
}
