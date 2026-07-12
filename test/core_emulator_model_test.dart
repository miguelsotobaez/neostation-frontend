import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/core_emulator_model.dart';

/// Builds a [CoreEmulatorModel] with only the field under test varying.
CoreEmulatorModel emu({String? package, bool isStandalone = false}) {
  return CoreEmulatorModel(
    uniqueId: 'test.emu',
    osId: 2, // android
    systemId: 'psx',
    name: 'Test Emulator',
    isStandalone: isStandalone,
    isDefault: false,
    isretroAchievementsCompatible: false,
    androidPackageName: package,
  );
}

void main() {
  group('CoreEmulatorModel.isRetroArch', () {
    test('is true for the base RetroArch package', () {
      expect(emu(package: 'com.retroarch').isRetroArch, isTrue);
    });

    test('is true for RetroArch variants (aarch64, ra32)', () {
      expect(emu(package: 'com.retroarch.aarch64').isRetroArch, isTrue);
      expect(emu(package: 'com.retroarch.ra32').isRetroArch, isTrue);
    });

    test('is false for standalone emulator packages', () {
      // The regression this guards: substituting one of these into a RetroArch
      // intent produced a package+activity mismatch (ACTIVITY_NOT_FOUND).
      expect(emu(package: 'com.github.stenzek.duckstation').isRetroArch, isFalse);
      expect(emu(package: 'org.azahar_emu.azahar').isRetroArch, isFalse);
      expect(emu(package: 'org.dolphinemu.dolphinemu').isRetroArch, isFalse);
    });

    test('is false when the package is null or empty', () {
      expect(emu(package: null).isRetroArch, isFalse);
      expect(emu(package: '').isRetroArch, isFalse);
    });

    test('is false for a package that merely contains "retroarch" mid-string', () {
      // Guards against a substring check regressing into startsWith.
      expect(emu(package: 'org.example.com.retroarch').isRetroArch, isFalse);
    });
  });
}
