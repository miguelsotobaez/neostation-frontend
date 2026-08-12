import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:neostation/services/logger_service.dart';
import 'region_config.dart';
import 'rom_hasher.dart';
import 'media_resolver.dart';
import 'screenscraper_client.dart';

/// Media asset downloader for ScreenScraper.
///
/// Downloads a game's media assets (boxart, screenshots, etc.) in bounded
/// concurrent batches, selecting the best regional/language variant, mapping
/// media types to folders, and skipping assets already on disk. Delegates
/// transport to [ScreenscraperClient], resolution to [ScreenscraperMediaResolver]
/// / [ScreenscraperRegionConfig], and ROM naming to [ScreenscraperRomHasher].
/// Extracted verbatim from [ScreenScraperService]; behaviour is unchanged.
/// Stateless — holds only the shared logger.
class ScreenscraperMediaDownloader {
  ScreenscraperMediaDownloader._();

  static final _log = LoggerService.instance;

  /// Removes stale artwork files that use a different image extension for the
  /// same media key.
  ///
  /// This matters for virtual libraries such as MeloNX: the initial library
  /// import can create a PNG fallback from MeloNX's `iconData`, while
  /// ScreenScraper later downloads the real cover/fanart as JPG. NeoStation's
  /// image resolver prefers PNG before JPG, so keeping both files makes the old
  /// fallback permanently win even though the ScreenScraper image downloaded
  /// successfully.
  static Future<void> _removeCompetingImageVariants(String fullPath) async {
    final targetExt = path.extension(fullPath).replaceFirst('.', '').toLowerCase();
    if (!const {'png', 'jpg', 'jpeg'}.contains(targetExt)) return;

    final base = path.withoutExtension(fullPath);
    for (final ext in const ['png', 'jpg', 'jpeg']) {
      if (ext == targetExt) continue;
      final sibling = File('$base.$ext');
      try {
        if (await sibling.exists()) {
          await sibling.delete();
        }
      } catch (_) {
        // A stale sibling that cannot be removed should not abort the scrape.
      }
    }
  }

  /// Downloads and caches a media file.
  static Future<bool> _downloadMediaFileSmart(
    String url,
    String relativePath,
    String userDataDir, {
    bool forceOverwrite = false,
    int? maxDailyRequests,
  }) async {
    try {
      final fullPath = path.join(userDataDir, relativePath);
      final file = File(fullPath);
      if (await file.exists() && !forceOverwrite) {
        // Even without a re-download, make the already-selected ScreenScraper
        // format authoritative by removing older PNG/JPG siblings.
        await _removeCompetingImageVariants(fullPath);
        return true;
      }

      final response = await ScreenscraperClient.httpGetWithRetry(
        Uri.parse(url),
        timeout: const Duration(seconds: 60),
        maxRetries: 2,
        maxDailyRequests: maxDailyRequests,
      );
      if (response.statusCode == 200) {
        await file.create(recursive: true);
        await file.writeAsBytes(response.bodyBytes);
        // The freshly downloaded ScreenScraper image must replace any older
        // fallback that has the same media key but a different extension.
        await _removeCompetingImageVariants(fullPath);
        return true;
      } else {
        _log.e('Error downloading media (${response.statusCode}): $url');
        return false;
      }
    } catch (e) {
      _log.e('Error downloading media: $e');
      return false;
    }
  }

  /// Downloads multiple media assets for a game, managing concurrency.
  static Future<Map<String, dynamic>> downloadGameMedia(
    String systemFolder,
    String romName,
    List<dynamic> medias,
    int maxThreads, {
    String? appSystemId,
    String? preferredLanguage,
    bool Function()? shouldCancel,
    Function(double progress)? onProgress,
    List<String>? allowedMediaTypes,
    bool forceOverwrite = false,
    int? maxDailyRequests,
  }) async {
    if (medias.isEmpty) {
      return {
        'success': true,
        'downloadedTypes': <String>[],
        'cancelled': false,
      };
    }

    final userDataDir = await ScreenscraperMediaResolver.getMediaDirectory();
    final regionPriority = await ScreenscraperRegionConfig.getRegionPriority();
    final mediaTypes =
        allowedMediaTypes ?? ['fanart', 'ss', 'video', 'wheel', 'box2D'];

    final downloadTasks = <Map<String, dynamic>>[];
    for (final mediaType in mediaTypes) {
      final bestMedia = ScreenscraperMediaResolver.selectBestMedia(
        medias,
        mediaType,
        preferredLanguage: preferredLanguage,
        regionPriority: regionPriority,
      );
      if (bestMedia != null) {
        final folderName = ScreenscraperMediaResolver.mapMediaTypeToFolder(
          mediaType,
        );
        final romBaseName = await ScreenscraperRomHasher.getCleanRomName(
          romName,
          appSystemId,
        );
        final fileName =
            '$romBaseName.${bestMedia['format']?.toString() ?? 'png'}';
        final relativePath = '$systemFolder/$folderName/$fileName';

        downloadTasks.add({
          'url': bestMedia['url'].toString(),
          'relativePath': relativePath,
          'mediaType': mediaType,
        });
      }
    }

    if (downloadTasks.isEmpty) {
      return {
        'success': true,
        'downloadedTypes': <String>[],
        'cancelled': false,
      };
    }

    final batches = <List<Map<String, dynamic>>>[];
    for (var i = 0; i < downloadTasks.length; i += maxThreads) {
      final end = (i + maxThreads < downloadTasks.length)
          ? i + maxThreads
          : downloadTasks.length;
      batches.add(downloadTasks.sublist(i, end));
    }

    final downloadedTypes = <String>[];
    final existingTypes = <String>[];
    bool wasCancelled = false;

    int completedTasks = 0;
    for (final batch in batches) {
      if (shouldCancel != null && shouldCancel()) {
        wasCancelled = true;
        break;
      }

      final futures = batch.map((task) async {
        final success = await _downloadMediaFileSmart(
          task['url'],
          task['relativePath'],
          userDataDir,
          forceOverwrite: forceOverwrite,
          maxDailyRequests: maxDailyRequests,
        );
        return {
          'mediaType': task['mediaType'],
          'success': success,
          'wasExisting':
              !forceOverwrite &&
              success &&
              await ScreenscraperMediaResolver.checkFileExists(
                task['relativePath'],
                userDataDir,
              ),
        };
      });

      final results = await Future.wait(futures);

      for (final result in results) {
        if (result['success'] == true) {
          if (result['wasExisting'] as bool) {
            existingTypes.add(result['mediaType'] as String);
          } else {
            downloadedTypes.add(result['mediaType'] as String);
          }
        }
      }

      completedTasks += batch.length;
      if (onProgress != null) onProgress(completedTasks / downloadTasks.length);

      if (batches.length > 1) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    final totalAvailable = downloadedTypes.length + existingTypes.length;
    return {
      'success': totalAvailable == downloadTasks.length && !wasCancelled,
      'downloadedTypes': downloadedTypes,
      'existingTypes': existingTypes,
      'cancelled': wasCancelled,
    };
  }
}
