import 'dart:isolate';

import 'package:neostation/services/logger_service.dart';
import '../../repositories/system_repository.dart';
import '../../utils/optimized_md5_utils.dart';

/// ROM identity helpers for ScreenScraper lookups.
///
/// Computes the file MD5 (off the UI isolate) used to fingerprint a ROM and
/// strips system-specific extensions from a ROM filename before a name-based
/// search. Extracted verbatim from [ScreenScraperService]; behaviour is
/// unchanged. Stateless — holds only the shared logger.
class ScreenscraperRomHasher {
  ScreenscraperRomHasher._();

  static final _log = LoggerService.instance;

  /// Computes the file MD5 hash in a background isolate to keep the UI responsive.
  static Future<String> calculateMd5InIsolate(String filePath) async {
    return await Isolate.run(() async {
      return await OptimizedMd5Utils.calculateFileMd5(filePath);
    });
  }

  /// Sanitizes a ROM filename by removing system-specific extensions.
  static Future<String> getCleanRomName(
    String romName,
    String? appSystemId,
  ) async {
    if (appSystemId != null) {
      try {
        final extensions = await SystemRepository.getExtensionsForSystem(
          appSystemId,
        );
        for (final ext in extensions) {
          final dotExt = '.$ext';
          if (romName.toLowerCase().endsWith(dotExt.toLowerCase())) {
            return romName.substring(0, romName.length - dotExt.length);
          }
        }
      } catch (e) {
        _log.w('Error getting extensions for app system $appSystemId: $e');
      }
    }

    final lastDot = romName.lastIndexOf('.');
    if (lastDot != -1) {
      final ext = romName.substring(lastDot + 1);
      if (!ext.contains(' ') && ext.length <= 10) {
        return romName.substring(0, lastDot);
      }
    }

    return romName;
  }
}
