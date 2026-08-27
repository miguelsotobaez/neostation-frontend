import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/gamepad/gamepad_navigation_manager.dart';

class _LayerRecorder {
  final List<String> history = [];

  void push(String id, {bool modal = false}) {
    GamepadNavigationManager.pushLayer(
      id,
      onActivate: () => history.add('+$id'),
      onDeactivate: () => history.add('-$id'),
      modal: modal,
    );
  }

  void pop(String id) => GamepadNavigationManager.popLayer(id);
}

void main() {
  group('GamepadNavigationManager Modal Layer Trapping for Collections & Dialogs', () {
    late _LayerRecorder r;

    setUp(() {
      r = _LayerRecorder();
    });

    test(
      'CollectionOptionsDropdown as modal isolates focus from CollectionsOverview grid',
      () {
        r.push('collections_grid', modal: false);
        expect(r.history, ['+collections_grid']);

        r.history.clear();
        r.push('collection_options_overlay', modal: true);
        expect(r.history, ['-collections_grid', '+collection_options_overlay']);

        r.history.clear();
        // Background async update tries to push a grid layer
        r.push('background_refresh_layer', modal: false);
        expect(r.history, isEmpty);

        // Popping modal returns focus to the active grid
        r.pop('collection_options_overlay');
        expect(r.history, [
          '-collection_options_overlay',
          '+background_refresh_layer',
        ]);
      },
    );

    test(
      'CreateEditCollectionDialog modal traps input and restores SystemGamesList on dismiss',
      () {
        r.push('system_games_list', modal: false);
        r.history.clear();

        r.push('create_edit_collection_dialog', modal: true);
        expect(r.history, [
          '-system_games_list',
          '+create_edit_collection_dialog',
        ]);

        r.history.clear();
        r.pop('create_edit_collection_dialog');
        expect(r.history, [
          '-create_edit_collection_dialog',
          '+system_games_list',
        ]);
      },
    );

    test(
      'Stacked modals: CollectionOptionsDropdown -> ConfirmActionDialog cascades focus cleanly',
      () {
        r.push('system_games_list', modal: false);
        r.push('collection_options_overlay', modal: true);
        r.history.clear();

        // Opening delete confirmation from collection options
        r.push('confirm_action_dialog', modal: true);
        expect(r.history, [
          '-collection_options_overlay',
          '+confirm_action_dialog',
        ]);

        // Canceling delete confirmation returns focus to collection options
        r.history.clear();
        r.pop('confirm_action_dialog');
        expect(r.history, [
          '-confirm_action_dialog',
          '+collection_options_overlay',
        ]);

        // Closing collection options returns focus to game list
        r.history.clear();
        r.pop('collection_options_overlay');
        expect(r.history, [
          '-collection_options_overlay',
          '+system_games_list',
        ]);
      },
    );

    test(
      'GameCollectionsDropdown overlay isolates favorite quick toggle from game list',
      () {
        r.push('system_games_list', modal: false);
        r.history.clear();

        r.push('game_collections_overlay', modal: true);
        expect(r.history, ['-system_games_list', '+game_collections_overlay']);

        r.history.clear();
        r.pop('game_collections_overlay');
        expect(r.history, ['-game_collections_overlay', '+system_games_list']);
      },
    );
  });
}
