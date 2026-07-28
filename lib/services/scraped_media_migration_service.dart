import 'dart:io';

import 'package:path/path.dart' as path;

import 'package:neostation/services/config_service.dart';
import 'package:neostation/services/logger_service.dart';

/// Renames scraped media after a multi-disc game is represented by an M3U.
class ScrapedMediaMigrationService {
  static final _log = LoggerService.instance;
  static const _mediaTypes = [
    'fanarts',
    'screenshots',
    'wheels',
    'box2d',
    'videos',
  ];

  static Future<void> useDiscOneMediaForPlaylist({
    required String systemFolder,
    required List<String> discFilenames,
    required String playlistFilename,
  }) async {
    if (discFilenames.isEmpty) return;

    try {
      final mediaPath = await ConfigService.getMediaPath();
      final discOneBase = path.basenameWithoutExtension(discFilenames.first);
      final playlistBase = path.basenameWithoutExtension(playlistFilename);
      final discardedBases = discFilenames
          .skip(1)
          .map(path.basenameWithoutExtension)
          .toSet();

      for (final mediaType in _mediaTypes) {
        final directory = Directory(
          path.join(mediaPath, systemFolder, mediaType),
        );
        if (!await directory.exists()) continue;

        await for (final entity in directory.list(followLinks: false)) {
          if (entity is! File) continue;
          final base = path.basenameWithoutExtension(entity.path);
          if (base == discOneBase) {
            final target = File(
              path.join(
                directory.path,
                '$playlistBase${path.extension(entity.path)}',
              ),
            );
            if (await target.exists()) await target.delete();
            await entity.rename(target.path);
          } else if (discardedBases.contains(base)) {
            await entity.delete();
          }
        }
      }
    } catch (e) {
      _log.e('Error migrating scraped media to playlist: $e');
    }
  }
}
