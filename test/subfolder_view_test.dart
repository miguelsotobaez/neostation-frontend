import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/system_model.dart';

/// Minimal [SystemModel] with only the always-required fields populated.
SystemModel system({bool subfolderView = false}) => SystemModel(
  folderName: 'nes',
  realName: 'NES',
  iconImage: 'assets/images/systems/icons/nes-icon.png',
  color: '#2697FF',
  subfolderView: subfolderView,
);

void main() {
  group('SystemModel.subfolderView serialization', () {
    test('defaults to false', () {
      expect(system().subfolderView, isFalse);
    });

    test('copyWith updates the flag and omitting preserves it', () {
      final base = system();
      expect(base.copyWith(subfolderView: true).subfolderView, isTrue);
      // Omitting the field keeps the previous value.
      expect(
        base.copyWith(subfolderView: true).copyWith().subfolderView,
        isTrue,
      );
    });

    test('round-trips through toJson/fromJson', () {
      final restored = SystemModel.fromJson(
        system(subfolderView: true).toJson(),
      );
      expect(restored.subfolderView, isTrue);
    });

    test('fromJson parses int, bool, and absent keys', () {
      SystemModel from(Map<String, dynamic> extra) => SystemModel.fromJson({
        'folder_name': 'nes',
        'real_name': 'NES',
        'icon_image': 'nes-icon.png',
        'color': '#2697FF',
        ...extra,
      });

      expect(from({'subfolder_view': 1}).subfolderView, isTrue);
      expect(from({'subfolder_view': 0}).subfolderView, isFalse);
      expect(from({'subfolder_view': 'true'}).subfolderView, isTrue);
      // Absent key falls back to the disabled default.
      expect(from({}).subfolderView, isFalse);
    });
  });
}
