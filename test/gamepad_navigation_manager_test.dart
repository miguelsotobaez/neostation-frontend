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
}
