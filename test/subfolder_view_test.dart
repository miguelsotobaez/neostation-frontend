import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/utils/rom_tree.dart';

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

  group('folderRelPathFor (deep-link landing level)', () {
    const roots = ['/storage/emulated/0/roms/nes'];

    test('a game in the system root reports the root level', () {
      expect(
        folderRelPathFor('/storage/emulated/0/roms/nes/Game.zip', roots),
        '',
      );
    });

    test('a game in a subfolder reports that folder', () {
      expect(
        folderRelPathFor(
          '/storage/emulated/0/roms/nes/Hacks (NES)/Game.zip',
          roots,
        ),
        'Hacks (NES)',
      );
    });

    test('nested folders report the full relative path', () {
      expect(
        folderRelPathFor(
          '/storage/emulated/0/roms/nes/Hacks (NES)/Sub/Game.zip',
          roots,
        ),
        'Hacks (NES)/Sub',
      );
    });

    test('a path outside every root, or no path at all, reports null', () {
      expect(folderRelPathFor('/somewhere/else/Game.zip', roots), isNull);
      expect(folderRelPathFor(null, roots), isNull);
      expect(folderRelPathFor('', roots), isNull);
      // No roots resolved yet (e.g. subfolder view off) is also "unknown".
      expect(
        folderRelPathFor('/storage/emulated/0/roms/nes/G.zip', const []),
        isNull,
      );
    });

    test('an Android SAF content URI resolves to its decoded folder', () {
      expect(
        folderRelPathFor(
          'content://com.android.externalstorage.documents/document/'
          'primary%3Aroms%2Fnes%2FHacks%20(NES)%2FGame.zip',
          const ['roms/nes'],
        ),
        'Hacks (NES)',
      );
    });

    test('the matching root wins when a system has several', () {
      expect(
        folderRelPathFor('/mnt/sd/roms/nes/Translations/G.zip', const [
          '/storage/emulated/0/roms/nes',
          '/mnt/sd/roms/nes',
        ]),
        'Translations',
      );
    });
  });
}
