import '../models/game_model.dart';
import '../models/secondary_achievement_item.dart';
import '../providers/retro_achievements_provider.dart';
import 'logger_service.dart';
import 'retro_achievements_matcher.dart';
import 'retroachievements_hash_service.dart';

/// A condensed snapshot of a game's RetroAchievements progress, ready to be
/// pushed to the secondary display.
class SecondaryAchievementsSnapshot {
  /// RetroAchievements internal game id.
  final int gameId;

  /// Standardized game title from RA.
  final String gameTitle;

  /// Achievements for the game (unsorted; the panel sorts unlocked-first).
  final List<SecondaryAchievementItem> achievements;

  /// Number of achievements the user has earned.
  final int earned;

  /// Total number of achievements available for the game.
  final int total;

  /// Points the user has earned.
  final int points;

  /// Total points available for the game.
  final int pointsTotal;

  /// User completion percentage string (e.g. '50.00%').
  final String completionPct;

  const SecondaryAchievementsSnapshot({
    required this.gameId,
    required this.gameTitle,
    required this.achievements,
    required this.earned,
    required this.total,
    required this.points,
    required this.pointsTotal,
    required this.completionPct,
  });

  /// The set of achievement ids the user has earned, for session-diffing.
  Set<int> get earnedIds =>
      achievements.where((a) => a.earned).map((a) => a.id).toSet();
}

/// Fetches a condensed RetroAchievements progress snapshot for the secondary
/// display.
///
/// Identification is [RetroAchievementsMatcher]'s job and is shared with the
/// main display, so the two screens cannot disagree about which game is
/// running. This adds only the snapshot the secondary panel renders.
class RetroAchievementsResolver {
  static final _log = LoggerService.instance;

  /// Resolves and fetches a condensed achievements snapshot for [game].
  ///
  /// Returns null when RA is disconnected, the game cannot be matched, or no
  /// achievement data is available. Reuses the provider's in-memory cache.
  static Future<SecondaryAchievementsSnapshot?> fetchSnapshot({
    required GameModel game,
    required String systemFolderName,
    required RetroAchievementsProvider provider,
    bool forceRefresh = false,
  }) async {
    if (!provider.isConnected) return null;

    try {
      final policy = await RetroAchievementsHashService.policyForSystem(
        game.systemFolderName,
      );
      final md5Hash = await RetroAchievementsMatcher.resolveMd5Hash(
        game,
        policy: policy,
      );
      final gameId = await RetroAchievementsMatcher.resolveGameId(
        game: game,
        systemFolderName: systemFolderName,
        summary: provider.userSummary,
        policy: policy,
        md5Hash: md5Hash,
      );
      if (gameId == null) return null;

      final info = await provider.getGameInfoAndUserProgress(
        gameId,
        forceRefresh: forceRefresh,
        md5Hash: md5Hash,
      );
      if (info == null || info.achievements.isEmpty) return null;

      final items = info.achievements.values.map((a) {
        final earnedHardcore =
            a.dateEarnedHardcore != null && a.dateEarnedHardcore!.isNotEmpty;
        final earned =
            earnedHardcore ||
            (a.dateEarned != null && a.dateEarned!.isNotEmpty);
        return SecondaryAchievementItem(
          id: a.id,
          title: a.title,
          description: a.description,
          points: a.points,
          badgeName: a.badgeName,
          displayOrder: a.displayOrder,
          type: a.type,
          earned: earned,
          earnedHardcore: earnedHardcore,
        );
      }).toList();

      final pointsTotal = items.fold<int>(0, (sum, a) => sum + a.points);
      final pointsEarned = items
          .where((a) => a.earned)
          .fold<int>(0, (sum, a) => sum + a.points);

      return SecondaryAchievementsSnapshot(
        gameId: gameId,
        gameTitle: info.title,
        achievements: items,
        earned: info.numAwardedToUser,
        total: info.numAchievements,
        points: pointsEarned,
        pointsTotal: pointsTotal,
        completionPct: info.userCompletion,
      );
    } catch (e) {
      _log.e('RA resolver: failed to fetch snapshot for ${game.name}: $e');
      return null;
    }
  }
}
