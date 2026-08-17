import 'package:flutter/material.dart';

import '../models/game_model.dart';
import '../models/retro_achievements_game_info.dart';
import '../models/system_model.dart';
import '../providers/retro_achievements_provider.dart';
import '../services/retro_achievements_matcher.dart';
import '../services/retroachievements_hash_service.dart';

/// Loads RetroAchievements metadata for a game shown on the main display.
///
/// The identification itself lives in [RetroAchievementsMatcher], which the
/// secondary display shares; this adds the main display's own concerns — the
/// "All" mode folder choice, the provider call, and badge-image eviction.
class RetroAchievementsHelper {
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

    final hasSpecificGenerator =
        RetroAchievementsHashService.hasSpecificHashGenerator(
          game.systemFolderName,
        );

    final md5Hash = await RetroAchievementsMatcher.resolveMd5Hash(
      game,
      hasSpecificGenerator: hasSpecificGenerator,
    );

    // In "All" mode the game carries its own system; a system view searches the
    // folder the user is browsing.
    final systemFolderName = isAllMode && game.systemFolderName != null
        ? game.systemFolderName!
        : effectiveSystem.primaryFolderName;

    final gameId = await RetroAchievementsMatcher.resolveGameId(
      game: game,
      systemFolderName: systemFolderName,
      summary: provider.userSummary,
      hasSpecificGenerator: hasSpecificGenerator,
      md5Hash: md5Hash,
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
}
