import 'dart:io';
import 'package:flutter/services.dart';
import 'package:neostation/models/core_emulator_model.dart';
import 'package:neostation/models/system_model.dart';
import 'package:neostation/repositories/emulator_repository.dart';
import 'package:neostation/services/logger_service.dart';

/// Hydrates the list of supported emulators for [system], verifying package
/// presence on Android hosts and RetroArch core availability on desktop.
///
/// Shared by the game details settings tab and the game settings dialog so
/// both enumerate identical emulator options.
Future<List<CoreEmulatorModel>> loadEmulatorsForSystem(
  SystemModel system,
) async {
  final log = LoggerService.instance;
  final systemId = system.id;
  if (systemId == null) return [];
  try {
    var emulators = await EmulatorRepository.getEmulatorsForSystemCurrentOs(
      systemId,
    );
    if (Platform.isAndroid) {
      // Verification Protocol: Check native package presence via platform channel.
      final updated = <CoreEmulatorModel>[];
      for (final e in emulators) {
        if (e.androidPackageName != null && e.androidPackageName!.isNotEmpty) {
          try {
            const ch = MethodChannel('com.neogamelab.neostation/game');
            var installed =
                await ch.invokeMethod<bool>('isPackageInstalled', {
                  'packageName': e.androidPackageName,
                }) ??
                false;

            // A RetroArch entry reports its *app* as installed even when the
            // specific libretro core (.so) isn't present, which made uninstalled
            // cores show "Ready" and get auto-selected → "Launch error" (#192).
            // Verify the core file. Tri-state: null means we couldn't determine
            // (RetroArch's cores dir is private and no root) → fail OPEN and leave
            // the package-based result untouched.
            if (installed &&
                e.isRetroArch &&
                e.coreFilename != null &&
                e.coreFilename!.isNotEmpty) {
              final coreInstalled = await ch.invokeMethod<bool>(
                'isCoreInstalled',
                {
                  'packageName': e.androidPackageName,
                  'coreFilename': e.coreFilename,
                },
              );
              if (coreInstalled != null) installed = coreInstalled;
            }
            updated.add(e.copyWith(isInstalled: installed));
          } catch (_) {
            updated.add(e);
          }
        } else {
          updated.add(e);
        }
      }
      emulators = updated;
    } else {
      // Desktop: a RetroArch core is only usable when its libretro core file
      // actually exists — having the RetroArch executable configured is not
      // enough (#192). Probe the cores dir next to the executable. If we can't
      // locate a readable cores dir (layout varies by platform/install), fail
      // OPEN and keep the executable-based assumption rather than hide a
      // genuinely-installed core.
      final retroArchPath =
          await EmulatorRepository.getRetroArchExecutablePath();

      // Baseline: on desktop a configured executable path is the only evidence
      // the database holds, so it stands in as the install verdict for anything
      // the core probe below does not refine. Without this, emulators would be
      // reported uninstalled whenever RetroArch itself is unconfigured.
      emulators = emulators
          .map((e) => e.copyWith(isInstalled: e.hasConfiguredPath))
          .toList();

      if (retroArchPath != null && retroArchPath.isNotEmpty) {
        final coresDir =
            '${File(retroArchPath).parent.path}'
            '${Platform.pathSeparator}cores';
        final coresDirReadable = await Directory(coresDir).exists();
        final updated = <CoreEmulatorModel>[];
        for (final e in emulators) {
          final uid = e.uniqueId;
          final isRaCore =
              uid.contains('.ra.') ||
              uid.contains('.ra32.') ||
              uid.contains('.ra64.');
          if (isRaCore && !e.hasConfiguredPath) {
            var installed = true; // fail-open default
            if (coresDirReadable &&
                e.coreFilename != null &&
                e.coreFilename!.isNotEmpty) {
              installed = await _desktopCoreExists(coresDir, e.coreFilename!);
            }
            updated.add(e.copyWith(isInstalled: installed));
          } else {
            updated.add(e); // keeps the baseline set above
          }
        }
        emulators = updated;
      }
    }
    return emulators;
  } catch (e) {
    log.e('Emulator enumeration failed: $e');
    return [];
  }
}

/// Returns whether a libretro core exists in [coresDir] on a desktop host.
///
/// The DB [coreFilename] may carry the Android-style name (e.g.
/// `ppsspp_libretro_android.so`), whereas desktop cores are named
/// `<base>_libretro.{dll,so,dylib}`. We therefore strip the known libretro
/// suffixes down to the base and probe each desktop extension, so a correct
/// core install isn't missed due to a platform naming mismatch.
Future<bool> _desktopCoreExists(String coresDir, String coreFilename) async {
  const suffixes = [
    '_libretro_android.so',
    '_libretro.so',
    '_libretro.dll',
    '_libretro.dylib',
  ];
  var base = coreFilename;
  for (final s in suffixes) {
    if (base.endsWith(s)) {
      base = base.substring(0, base.length - s.length);
      break;
    }
  }
  for (final ext in const [
    '_libretro.dll',
    '_libretro.so',
    '_libretro.dylib',
  ]) {
    if (await File('$coresDir${Platform.pathSeparator}$base$ext').exists()) {
      return true;
    }
  }
  return false;
}
