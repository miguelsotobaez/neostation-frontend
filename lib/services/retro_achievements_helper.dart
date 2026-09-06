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

  /// The RetroAchievements game id each ROM last resolved to.
  ///
  /// Resolution is asynchronous — a manual-match read, a hash lookup, then a
  /// filename lookup, each a database round trip — so a game the app has
  /// already identified still costs a frame to identify again. Remembering the
  /// answer is what lets [cachedGameInfo] hand the caller the data it already
  /// holds without one.
  ///
  /// Keyed by ROM path, so it survives the [GameModel] being rebuilt by a
  /// scrape or a favourite toggle. Cleared by [forgetResolvedIds] when a manual
  /// match makes the stored answers wrong.
  static final Map<String, int> _resolvedGameIds = {};

  static String? _memoKey(GameModel game) {
    final romPath = game.romPath;
    if (romPath != null && romPath.isNotEmpty) return romPath;
    return game.romname.isNotEmpty ? game.romname : null;
  }

  /// The already-loaded metadata for [game], or `null` if answering would need
  /// any I/O.
  ///
  /// Both halves have to be in memory: the id this ROM resolved to on an
  /// earlier visit, and the provider's cached response for that id. When they
  /// are, a caller can adopt the result in the same frame the selection
  /// changed and never show a loading state for a lookup that has nothing to
  /// look up.
  static GameInfoAndUserProgress? cachedGameInfo({
    required GameModel game,
    required RetroAchievementsProvider provider,
  }) {
    if (!provider.isConnected) return null;
    final key = _memoKey(game);
    if (key == null) return null;
    final gameId = _resolvedGameIds[key];
    if (gameId == null) return null;
    return provider.gameInfoCache[gameId];
  }

  /// Drops every remembered resolution.
  ///
  /// Called when a manual match is chosen: the id a ROM resolved to before is
  /// exactly what the user has just overridden.
  static void forgetResolvedIds() => _resolvedGameIds.clear();

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

    final policy = await RetroAchievementsHashService.policyForSystem(
      game.systemFolderName,
    );

    final md5Hash = await RetroAchievementsMatcher.resolveMd5Hash(
      game,
      policy: policy,
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
      policy: policy,
      md5Hash: md5Hash,
    );

    if (gameId == null) return null;

    // Remember what this ROM resolved to, so the next visit can read the
    // provider's cache directly instead of re-deriving the id.
    final key = _memoKey(game);
    if (key != null) _resolvedGameIds[key] = gameId;

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
