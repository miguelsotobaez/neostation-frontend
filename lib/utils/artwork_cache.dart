import 'dart:io';

import 'package:flutter/painting.dart';

import '../models/game_model.dart';
import '../providers/file_provider.dart';

/// The media folders a single-game scrape can add to or overwrite.
const List<String> scrapedArtworkTypes = [
  'fanarts',
  'wheels',
  'box2d',
  'screenshots',
];

/// Resolves every artwork file a scrape may have written for [game].
List<String> scrapedArtworkPaths(
  GameModel game,
  String systemFolderName, [
  FileProvider? fileProvider,
]) {
  return [
    for (final type in scrapedArtworkTypes)
      game.getImagePath(systemFolderName, type, fileProvider),
  ];
}

/// Drops every cached decode of the given artwork [paths] so the next build
/// reads them from disk again.
///
/// Evicting the [FileImage] alone is not enough: the game views render artwork
/// through `Image.file(..., cacheWidth: n)`, which wraps the provider in a
/// [ResizeImage] and caches the resized bitmap under the ResizeImage key. The
/// widths differ per view (256, 388, 512, 640, 1024, 1920), so clearing is the
/// only path-agnostic way to reach every variant — without it a re-scrape kept
/// showing the old art until something unrelated cleared the cache.
///
/// Callers must also give the affected widgets a new key (see the
/// `artworkVersion` / `imageVersion` counters), because an [Image] whose
/// provider compares equal never re-resolves on its own.
Future<void> evictScrapedArtwork(Iterable<String> paths) async {
  for (final path in paths) {
    if (path.isEmpty) continue;
    try {
      final file = File(path);
      if (await file.exists()) {
        await FileImage(file).evict();
      }
    } catch (_) {
      // An unreadable file has nothing cached to evict.
    }
  }

  final imageCache = PaintingBinding.instance.imageCache;
  imageCache.clear();
  imageCache.clearLiveImages();
}
