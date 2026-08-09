import 'dart:io';

import 'package:flutter/material.dart';

import '../models/game_model.dart';
import '../models/retro_achievements_game_info.dart';
import '../models/system_model.dart';
import '../providers/retro_achievements_provider.dart';
import '../repositories/retro_achievements_repository.dart';
import '../services/logger_service.dart';
import '../services/retroachievements_hash_service.dart';

/// Reusable helper for resolving a local game to its RetroAchievements metadata.
///
/// Encapsulates the multi-step identification pipeline (hash generation, local
/// database lookups, filename normalization, and recent-history heuristics) so
/// it can be reused by both the details card and standalone achievement dialogs.
class RetroAchievementsHelper {
  static final _log = LoggerService.instance;

  RetroAchievementsHelper._();

  /// Loads RetroAchievements metadata for [game].
  ///
  /// Returns `null` when the user is not connected, the game cannot be
  /// identified, or the API call fails.
  static Future<GameInfoAndUserProgress?> loadGameInfo({
    required GameModel game,
    required RetroAchievementsProvider provider,
    required SystemModel effectiveSystem,
    bool isAllMode = false,
    bool forceRefresh = false,
  }) async {
    if (!provider.isConnected) return null;

    final summary = provider.userSummary;

    final hasSpecificGenerator =
        RetroAchievementsHashService.hasSpecificHashGenerator(
          game.systemFolderName,
        );

    String? md5Hash = game.raHash;

    if (hasSpecificGenerator) {
      if (md5Hash == null || md5Hash.isEmpty) {
        md5Hash = await RetroAchievementsHashService.generateHashForGame(game);
      }
    } else {
      if (md5Hash == null || md5Hash.isEmpty) {
        if (game.romPath != null) {
          final file = File(game.romPath!);
          if (await file.exists()) {
            final fileSize = await file.length();
            const maxSize = 512 * 1024 * 1024;
            if (fileSize < maxSize) {
              md5Hash = await RetroAchievementsHashService.generateHashForGame(
                game,
              );
            }
          }
        }
      }
    }

    final gameId = await _findGameId(
      game: game,
      summary: summary,
      md5Hash: md5Hash,
      hasSpecificGenerator: hasSpecificGenerator,
      effectiveSystem: effectiveSystem,
      isAllMode: isAllMode,
    );

    if (gameId == null) return null;

    return provider.getGameInfoAndUserProgress(
      gameId,
      forceRefresh: forceRefresh,
      md5Hash: md5Hash,
    );
  }

  /// Evicts previously cached achievement badge images so a forced refresh
  /// displays updated artwork.
  static void evictBadgeCache(GameInfoAndUserProgress? gameInfo) {
    if (gameInfo == null) return;
    for (final ach in gameInfo.achievements.values) {
      final baseUrl =
          'https://media.retroachievements.org/Badge/${ach.badgeName}';
      NetworkImage('$baseUrl.png').evict();
      NetworkImage('${baseUrl}_lock.png').evict();
    }
  }

  static Future<int?> _findGameId({
    required GameModel game,
    required dynamic summary,
    required String? md5Hash,
    required bool hasSpecificGenerator,
    required SystemModel effectiveSystem,
    required bool isAllMode,
  }) async {
    // Strategy 1: Exact hash matching against the local RA database.
    if (md5Hash != null && md5Hash.isNotEmpty) {
      try {
        final gameId = await RetroAchievementsRepository.findGameIdByHash(
          md5Hash,
        );
        if (gameId != null) return gameId;
      } catch (e) {
        _log.e('Hash lookup failure: $e');
      }
    }

    if (hasSpecificGenerator) return null;

    // Strategy 2: Filename normalization and metadata matching.
    try {
      var filenameWithoutExt = game.romname.contains('.')
          ? game.romname.substring(0, game.romname.lastIndexOf('.'))
          : game.romname;

      filenameWithoutExt = filenameWithoutExt
          .replaceAll(RegExp(r'\([^)]*\)'), '')
          .replaceAll(RegExp(r'\[[^\]]*\]'), '')
          .trim();

      final systemFolderName = isAllMode && game.systemFolderName != null
          ? game.systemFolderName!
          : effectiveSystem.primaryFolderName;

      final gameId = await RetroAchievementsRepository.findGameIdByFilename(
        systemFolderName,
        filenameWithoutExt,
      );
      if (gameId != null) return gameId;
    } catch (e) {
      _log.e('Database metadata search failed: $e');
    }

    // Strategy 3: Heuristic matching against the user's recent play history.
    try {
      final gameName = game.name.toLowerCase();
      final normalizedLocal = gameName
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .toLowerCase();

      for (final recentlyPlayed in summary?.recentlyPlayed ?? const []) {
        final raGameName = recentlyPlayed.title.toLowerCase();
        final normalizedRA = raGameName
            .replaceAll(RegExp(r'[^\w\s]'), '')
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim()
            .toLowerCase();

        if (normalizedLocal == normalizedRA) {
          return recentlyPlayed.gameId;
        }
      }
    } catch (e) {
      _log.e('Recent history metadata resolution failed: $e');
    }

    return null;
  }
}
