import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../logger_service.dart';
import 'media_resolver.dart';
import 'rom_hasher.dart';
import 'screenscraper_client.dart';

/// Targeted ScreenScraper media fallback for MeloNX virtual Nintendo Switch
/// rows.
///
/// MeloNX rows have no physical ROM file, so NeoStation identifies the game by
/// its exported title name. Once ScreenScraper returns a matching game we also
/// have the authoritative ScreenScraper game id. This helper can then request
/// artwork directly through ScreenScraper's mediaJeu.php endpoint when the
/// media URLs embedded in jeuInfos.php are missing or fail.
///
/// The fallback is intentionally scoped to MeloNX virtual rows so it cannot
/// change scraping behaviour for physical ROM libraries or other platforms.
class ScreenscraperMeloNxMediaFallback {
  ScreenscraperMeloNxMediaFallback._();

  static final _log = LoggerService.instance;
  static const String _baseUrl = 'https://api.screenscraper.fr/api2';
  static const String _debugFileName = 'melonx_scraper_media_debug.txt';

  /// Ensures the requested MeloNX image types exist on disk.
  ///
  /// [alreadyDownloadedTypes] comes from the normal NeoStation media downloader
  /// and prevents duplicate network requests. Existing MeloNX iconData fallback
  /// artwork is deliberately NOT treated as ScreenScraper success: if the
  /// normal downloader did not confirm a media type, this method may overwrite
  /// that fallback with ScreenScraper artwork.
  static Future<Map<String, dynamic>> ensureMediaByGameId({
    required String gameId,
    required String systemId,
    required String systemFolder,
    required String romName,
    required String appSystemId,
    required String devId,
    required String devPassword,
    required String softname,
    required String username,
    required String password,
    required List<String> allowedMediaTypes,
    required List<String> alreadyDownloadedTypes,
    required List<dynamic> sourceMedias,
    int? maxDailyRequests,
  }) async {
    final successful = <String>{...alreadyDownloadedTypes};
    final attempted = <String>[];
    final failures = <String>[];

    final imageTypes = allowedMediaTypes
        .where((type) => const ['fanart', 'ss', 'wheel', 'box2D'].contains(type))
        .toList();

    final sourceTypes = <String>{};
    final sourceRegionsByType = <String, List<String>>{};
    for (final raw in sourceMedias) {
      if (raw is! Map) continue;
      final type = raw['type']?.toString() ?? '';
      final region = raw['region']?.toString() ?? '';
      if (type.isEmpty) continue;
      sourceTypes.add(type);
      if (region.isNotEmpty) {
        sourceRegionsByType.putIfAbsent(type, () => <String>[]);
        if (!sourceRegionsByType[type]!.contains(region)) {
          sourceRegionsByType[type]!.add(region);
        }
      }
    }

    final mediaRoot = await ScreenscraperMediaResolver.getMediaDirectory();
    final romBaseName = await ScreenscraperRomHasher.getCleanRomName(
      romName,
      appSystemId,
    );

    await _writeDebug(
      'STATE: START\n'
      'Game ID: $gameId\n'
      'System ID: $systemId\n'
      'ROM key: $romName\n'
      'Media key: $romBaseName\n'
      'Allowed media: ${allowedMediaTypes.join(', ')}\n'
      'Normal downloader succeeded: ${alreadyDownloadedTypes.join(', ')}\n'
      'jeuInfos media count: ${sourceMedias.length}\n'
      'jeuInfos media types: ${sourceTypes.toList()..sort()}\n',
    );

    for (final mediaType in imageTypes) {
      final folder = ScreenscraperMediaResolver.mapMediaTypeToFolder(mediaType);
      final target = File(
        path.join(mediaRoot, systemFolder, folder, '$romBaseName.png'),
      );
      await target.parent.create(recursive: true);

      if (successful.contains(mediaType)) {
        final validExisting = await _findValidLocalImage(
          mediaRoot,
          systemFolder,
          folder,
          romBaseName,
        );
        if (validExisting != null) {
          await _appendDebug(
            '\nSKIP $mediaType: normal downloader produced a valid image '
            '(${validExisting.path}).',
          );
          continue;
        }

        // ScreenScraper can reply HTTP 200 with a small textual status such as
        // NOMEDIA. The generic downloader historically treated every HTTP 200
        // as a successful image download, so do not trust its success flag when
        // the resulting file is not actually an image.
        successful.remove(mediaType);
        await _deleteInvalidLocalImages(
          mediaRoot,
          systemFolder,
          folder,
          romBaseName,
        );
        await _appendDebug(
          '\nRETRY $mediaType: normal downloader reported success but no '
          'valid image exists on disk.',
        );
      }

      final candidateTokens = _candidateMediaTokens(
        mediaType,
        sourceRegionsByType,
      );

      var downloaded = false;
      for (final token in candidateTokens) {
        attempted.add('$mediaType:$token');
        final uri = Uri.parse('$_baseUrl/mediaJeu.php').replace(
          queryParameters: {
            'devid': devId,
            'devpassword': devPassword,
            'softname': softname,
            'ssid': username,
            'sspassword': password,
            'crc': '',
            'md5': '',
            'sha1': '',
            'systemeid': systemId,
            'jeuid': gameId,
            'media': token,
            // Force one predictable extension so NeoStation's image resolver
            // and the scraper always agree on the on-disk filename.
            'outputformat': 'png',
          },
        );

        try {
          final response = await ScreenscraperClient.httpGetWithRetry(
            uri,
            timeout: const Duration(seconds: 60),
            maxRetries: 1,
            maxDailyRequests: maxDailyRequests,
          );

          final contentType = response.headers['content-type'] ?? '';
          final bodyPrefix = _safeBodyPrefix(response.bodyBytes);
          final isImage = response.statusCode == 200 &&
              _looksLikeImage(response.bodyBytes, contentType);

          await _appendDebug(
            '\nTRY $mediaType -> $token\n'
            'HTTP: ${response.statusCode}\n'
            'Content-Type: $contentType\n'
            'Bytes: ${response.bodyBytes.length}\n'
            'Body prefix: $bodyPrefix\n'
            'Valid image: $isImage\n',
          );

          if (!isImage) continue;

          await target.writeAsBytes(response.bodyBytes, flush: true);
          successful.add(mediaType);
          downloaded = true;
          await _appendDebug('Saved: ${target.path}\n');
          break;
        } catch (e) {
          failures.add('$mediaType/$token: $e');
          await _appendDebug('\nERROR $mediaType -> $token: $e\n');
        }
      }

      if (!downloaded) {
        failures.add('$mediaType: no downloadable ScreenScraper media found');
        await _appendDebug(
          '\nFAILED $mediaType: no candidate returned a valid image.\n',
        );
      }
    }

    await _appendDebug(
      '\nSTATE: DONE\n'
      'Successful image types: ${successful.toList()..sort()}\n'
      'Attempts: ${attempted.length}\n'
      'Failures: ${failures.length}\n',
    );

    return {
      'successfulTypes': successful.toList(),
      'attempted': attempted,
      'failures': failures,
    };
  }

  static List<String> _candidateMediaTokens(
    String mediaType,
    Map<String, List<String>> sourceRegionsByType,
  ) {
    final regions = <String>[];

    void addRegion(String value) {
      final normalized = value.trim();
      if (normalized.isEmpty || regions.contains(normalized)) return;
      regions.add(normalized);
    }

    // First reuse regions ScreenScraper itself advertised for this game's
    // media payload. Then try a short, high-value fallback list. `cus` matters
    // for community/custom covers and is commonly present on newer systems.
    final relevantSourceTypes = switch (mediaType) {
      'wheel' => ['wheel-hd', 'wheel'],
      'ss' => ['ss-hd', 'ss'],
      'box2D' => ['box-2D'],
      'fanart' => ['fanart'],
      _ => [mediaType],
    };
    for (final sourceType in relevantSourceTypes) {
      for (final region in sourceRegionsByType[sourceType] ?? const <String>[]) {
        addRegion(region);
      }
    }
    for (final region in const ['wor', 'us', 'eu', 'jp', 'cus']) {
      addRegion(region);
    }

    switch (mediaType) {
      case 'fanart':
        // ScreenScraper documents fanart as a non-regional media, but some
        // responses still expose regional variants. Try plain first.
        return ['fanart', ...regions.map((r) => 'fanart($r)')];
      case 'ss':
        return [
          ...regions.map((r) => 'ss-hd($r)'),
          ...regions.map((r) => 'ss($r)'),
          'ss',
        ];
      case 'wheel':
        return [
          ...regions.map((r) => 'wheel-hd($r)'),
          ...regions.map((r) => 'wheel($r)'),
          'wheel-hd',
          'wheel',
        ];
      case 'box2D':
        return [...regions.map((r) => 'box-2D($r)'), 'box-2D'];
      default:
        return [mediaType];
    }
  }

  static Future<File?> _findValidLocalImage(
    String mediaRoot,
    String systemFolder,
    String folder,
    String romBaseName,
  ) async {
    for (final extension in const ['png', 'jpg', 'jpeg']) {
      final file = File(
        path.join(mediaRoot, systemFolder, folder, '$romBaseName.$extension'),
      );
      if (!await file.exists()) continue;
      try {
        final bytes = await file.readAsBytes();
        if (_looksLikeImage(bytes, '')) return file;
      } catch (_) {}
    }
    return null;
  }

  static Future<void> _deleteInvalidLocalImages(
    String mediaRoot,
    String systemFolder,
    String folder,
    String romBaseName,
  ) async {
    for (final extension in const ['png', 'jpg', 'jpeg']) {
      final file = File(
        path.join(mediaRoot, systemFolder, folder, '$romBaseName.$extension'),
      );
      if (!await file.exists()) continue;
      try {
        final bytes = await file.readAsBytes();
        if (!_looksLikeImage(bytes, '')) {
          await file.delete();
        }
      } catch (_) {
        try {
          await file.delete();
        } catch (_) {}
      }
    }
  }

  static bool _looksLikeImage(List<int> bytes, String contentType) {
    if (bytes.length < 4) return false;

    final prefix = _safeBodyPrefix(bytes).toUpperCase();
    if (prefix.startsWith('NOMEDIA') ||
        prefix.startsWith('CRCOK') ||
        prefix.startsWith('MD5OK') ||
        prefix.startsWith('SHA1OK') ||
        prefix.startsWith('<!DOCTYPE') ||
        prefix.startsWith('<HTML')) {
      return false;
    }

    final lowerType = contentType.toLowerCase();
    if (lowerType.startsWith('image/')) return true;

    final isPng = bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4e &&
        bytes[3] == 0x47 &&
        bytes[4] == 0x0d &&
        bytes[5] == 0x0a &&
        bytes[6] == 0x1a &&
        bytes[7] == 0x0a;
    if (isPng) return true;

    final isJpeg = bytes[0] == 0xff && bytes[1] == 0xd8 && bytes[2] == 0xff;
    if (isJpeg) return true;

    final isWebP = bytes.length >= 12 &&
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP';
    return isWebP;
  }

  static String _safeBodyPrefix(List<int> bytes) {
    if (bytes.isEmpty) return '<empty>';
    final take = bytes.length > 40 ? 40 : bytes.length;
    final text = utf8.decode(bytes.sublist(0, take), allowMalformed: true);
    return text.replaceAll(RegExp(r'[\r\n\t]+'), ' ').trim();
  }

  static Future<void> _writeDebug(String content) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(path.join(docs.path, _debugFileName));
      await file.writeAsString('--- ${DateTime.now()} ---\n$content');
    } catch (e) {
      _log.e('MeloNX media fallback: failed writing debug file: $e');
    }
  }

  static Future<void> _appendDebug(String content) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final file = File(path.join(docs.path, _debugFileName));
      await file.writeAsString(content, mode: FileMode.append);
    } catch (e) {
      _log.e('MeloNX media fallback: failed appending debug file: $e');
    }
  }
}
