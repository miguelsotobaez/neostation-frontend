import '../utils/ra_utils.dart';

/// Represents a game that the user has played recently on RetroAchievements.org.
class RecentlyPlayedGame {
  /// Unique game identifier.
  final int gameId;

  /// Internal platform identifier (e.g., 1 for NES).
  final int consoleId;

  /// Human-readable name of the console platform.
  final String consoleName;

  /// Full title of the game.
  final String title;

  /// Path to the game's icon image.
  final String imageIcon;

  /// Path to the game's title screen image.
  final String imageTitle;

  /// Path to a representative in-game screenshot.
  final String imageIngame;

  /// Path to the game's box art image.
  final String imageBoxArt;

  /// Timestamp indicating when the game was last launched.
  final String lastPlayed;

  /// Total number of achievements available for this game.
  final int achievementsTotal;

  RecentlyPlayedGame({
    required this.gameId,
    required this.consoleId,
    required this.consoleName,
    required this.title,
    required this.imageIcon,
    required this.imageTitle,
    required this.imageIngame,
    required this.imageBoxArt,
    required this.lastPlayed,
    required this.achievementsTotal,
  });

  /// Creates a [RecentlyPlayedGame] instance from a JSON-compatible map.
  factory RecentlyPlayedGame.fromJson(Map<String, dynamic> json) {
    return RecentlyPlayedGame(
      gameId: RAParsingUtils.toInt(json['GameID']),
      consoleId: RAParsingUtils.toInt(json['ConsoleID']),
      consoleName: (json['ConsoleName'] ?? '').toString(),
      title: (json['Title'] ?? '').toString(),
      imageIcon: (json['ImageIcon'] ?? '').toString(),
      imageTitle: (json['ImageTitle'] ?? '').toString(),
      imageIngame: (json['ImageIngame'] ?? '').toString(),
      imageBoxArt: (json['ImageBoxArt'] ?? '').toString(),
      lastPlayed: (json['LastPlayed'] ?? '').toString(),
      achievementsTotal: RAParsingUtils.toInt(json['AchievementsTotal']),
    );
  }
}

/// Statistics for achievements awarded to the user for a specific game.
class AwardedStats {
  /// Total number of achievements possible for the game.
  final int numPossibleAchievements;

  /// Maximum possible score achievable for this game.
  final int possibleScore;

  /// Number of achievements currently earned by the user (casual).
  final int numAchieved;

  /// Total score accumulated by the user for this game (casual).
  final int scoreAchieved;

  /// Number of achievements earned in hardcore mode.
  final int numAchievedHardcore;

  /// Total score accumulated by the user in hardcore mode.
  final int scoreAchievedHardcore;

  AwardedStats({
    required this.numPossibleAchievements,
    required this.possibleScore,
    required this.numAchieved,
    required this.scoreAchieved,
    required this.numAchievedHardcore,
    required this.scoreAchievedHardcore,
  });

  /// Creates an [AwardedStats] instance from a JSON-compatible map.
  factory AwardedStats.fromJson(Map<String, dynamic> json) {
    return AwardedStats(
      numPossibleAchievements: RAParsingUtils.toInt(
        json['NumPossibleAchievements'],
      ),
      possibleScore: RAParsingUtils.toInt(json['PossibleScore']),
      numAchieved: RAParsingUtils.toInt(json['NumAchieved']),
      scoreAchieved: RAParsingUtils.toInt(json['ScoreAchieved']),
      numAchievedHardcore: RAParsingUtils.toInt(json['NumAchievedHardcore']),
      scoreAchievedHardcore: RAParsingUtils.toInt(
        json['ScoreAchievedHardcore'],
      ),
    );
  }

  /// Returns the user's completion percentage (casual).
  double get completionPercentage {
    return numPossibleAchievements > 0
        ? (numAchieved / numPossibleAchievements) * 100
        : 0.0;
  }

  /// Returns the user's hardcore completion percentage.
  double get hardcoreCompletionPercentage {
    return numPossibleAchievements > 0
        ? (numAchievedHardcore / numPossibleAchievements) * 100
        : 0.0;
  }
}

/// Represents an achievement that has been recently earned by the user.
class RecentAchievement {
  /// Unique achievement identifier.
  final int id;

  /// Unique game identifier.
  final int gameId;

  /// Title of the game associated with the achievement.
  final String gameTitle;

  /// Title of the achievement.
  final String title;

  /// Short description of the achievement's requirements.
  final String description;

  /// Point value of the achievement.
  final int points;

  /// Achievement category (e.g., 'progression').
  final String type;

  /// Identifier for the achievement badge icon.
  final String badgeName;

  /// Whether the achievement has been awarded.
  final bool isAwarded;

  /// Timestamp when the achievement was earned.
  final String dateAwarded;

  /// Indicates if the achievement was earned in hardcore mode (1) or casual (0).
  final int hardcoreAchieved;

  RecentAchievement({
    required this.id,
    required this.gameId,
    required this.gameTitle,
    required this.title,
    required this.description,
    required this.points,
    required this.type,
    required this.badgeName,
    required this.isAwarded,
    required this.dateAwarded,
    required this.hardcoreAchieved,
  });

  /// Creates a [RecentAchievement] instance from a JSON-compatible map.
  factory RecentAchievement.fromJson(Map<String, dynamic> json) {
    return RecentAchievement(
      id: RAParsingUtils.toInt(json['ID']),
      gameId: RAParsingUtils.toInt(json['GameID']),
      gameTitle: (json['GameTitle'] ?? '').toString(),
      title: (json['Title'] ?? '').toString(),
      description: (json['Description'] ?? '').toString(),
      points: RAParsingUtils.toInt(json['Points']),
      type: (json['Type'] ?? '').toString(),
      badgeName: (json['BadgeName'] ?? '').toString(),
      isAwarded: RAParsingUtils.toBool(json['IsAwarded']),
      dateAwarded: (json['DateAwarded'] ?? '').toString(),
      hardcoreAchieved: RAParsingUtils.toInt(json['HardcoreAchieved']),
    );
  }
}

/// Comprehensive summary of a user's profile and activity on RetroAchievements.org.
class RetroAchievementsUserSummary {
  /// Username of the profile owner.
  final String user;

  /// Timestamp indicating when the user joined RetroAchievements.
  final String memberSince;

  /// Raw data representing the user's latest site activity.
  final Map<String, dynamic>? lastActivity;

  /// User's current Rich Presence status message.
  final String richPresenceMsg;

  /// ID of the last game launched by the user.
  final int lastGameId;

  /// Total count of developer contributions.
  final int contribCount;

  /// Contribution yield points.
  final int contribYield;

  /// Total points accumulated (Hardcore mode).
  final int totalPoints;

  /// Total points accumulated in casual mode.
  final int totalCasualPoints;

  /// Total weighted "True" points.
  final int totalTruePoints;

  /// User's permission level on the platform.
  final int permissions;

  /// Number of achievements earned in untracked games.
  final int untracked;

  /// Unique internal user identifier.
  final int id;

  /// Whether the user's profile wall is enabled.
  final bool userWallActive;

  /// User's custom status or motto.
  final String motto;

  /// Global rank of the user based on points.
  final int rank;

  /// Total count of games in the "Recently Played" list.
  final int recentlyPlayedCount;

  /// List of games recently launched by the user.
  final List<RecentlyPlayedGame> recentlyPlayed;

  /// Mapping of game IDs to their respective [AwardedStats].
  final Map<String, AwardedStats> awarded;

  /// Mapping of game IDs to a list of achievements recently earned in that game.
  final Map<String, List<RecentAchievement>> recentAchievements;

  /// Raw metadata for the last game played.
  final Map<String, dynamic>? lastGame;

  /// Unique internal identifier string (ULID).
  final String ulid;

  /// Relative path to the user's profile picture.
  final String userPic;

  /// Total number of users who are ranked.
  final int totalRanked;

  /// Current online status of the user.
  final String status;

  RetroAchievementsUserSummary({
    required this.user,
    required this.memberSince,
    this.lastActivity,
    required this.richPresenceMsg,
    required this.lastGameId,
    required this.contribCount,
    required this.contribYield,
    required this.totalPoints,
    required this.totalCasualPoints,
    required this.totalTruePoints,
    required this.permissions,
    required this.untracked,
    required this.id,
    required this.userWallActive,
    required this.motto,
    required this.rank,
    required this.recentlyPlayedCount,
    required this.recentlyPlayed,
    required this.awarded,
    required this.recentAchievements,
    this.lastGame,
    required this.ulid,
    required this.userPic,
    required this.totalRanked,
    required this.status,
  });

  /// Creates a [RetroAchievementsUserSummary] instance from an RA API response.
  factory RetroAchievementsUserSummary.fromJson(Map<String, dynamic> json) {
    final recentlyPlayedJson = json['RecentlyPlayed'] as List<dynamic>? ?? [];
    final recentlyPlayed = recentlyPlayedJson
        .map((game) => RecentlyPlayedGame.fromJson(game))
        .toList();

    final awardedJson = json['Awarded'] as Map<String, dynamic>? ?? {};
    final awarded = <String, AwardedStats>{};
    awardedJson.forEach((gameId, stats) {
      awarded[gameId] = AwardedStats.fromJson(stats);
    });

    final recentAchievementsJson = json['RecentAchievements'];
    final recentAchievements = <String, List<RecentAchievement>>{};

    if (recentAchievementsJson is Map<String, dynamic>) {
      recentAchievementsJson.forEach((gameId, achievements) {
        final achievementList = achievements as Map<String, dynamic>;
        final parsedAchievements = <RecentAchievement>[];
        achievementList.forEach((achievementId, achievementData) {
          parsedAchievements.add(RecentAchievement.fromJson(achievementData));
        });
        recentAchievements[gameId] = parsedAchievements;
      });
    }

    return RetroAchievementsUserSummary(
      user: (json['User'] ?? '').toString(),
      memberSince: (json['MemberSince'] ?? '').toString(),
      lastActivity: json['LastActivity'],
      richPresenceMsg: (json['RichPresenceMsg'] ?? '').toString(),
      lastGameId: RAParsingUtils.toInt(json['LastGameID']),
      contribCount: RAParsingUtils.toInt(json['ContribCount']),
      contribYield: RAParsingUtils.toInt(json['ContribYield']),
      totalPoints: RAParsingUtils.toInt(json['TotalPoints']),
      totalCasualPoints: RAParsingUtils.toInt(json['TotalSoftcorePoints']),
      totalTruePoints: RAParsingUtils.toInt(json['TotalTruePoints']),
      permissions: RAParsingUtils.toInt(json['Permissions']),
      untracked: RAParsingUtils.toInt(json['Untracked']),
      id: RAParsingUtils.toInt(json['ID']),
      userWallActive: RAParsingUtils.toBool(json['UserWallActive']),
      motto: (json['Motto'] ?? '').toString(),
      rank: RAParsingUtils.toInt(json['Rank']),
      recentlyPlayedCount: RAParsingUtils.toInt(json['RecentlyPlayedCount']),
      recentlyPlayed: recentlyPlayed,
      awarded: awarded,
      recentAchievements: recentAchievements,
      lastGame: json['LastGame'],
      ulid: (json['ULID'] ?? '').toString(),
      userPic: (json['UserPic'] ?? '').toString(),
      totalRanked: RAParsingUtils.toInt(json['TotalRanked']),
      status: (json['Status'] ?? '').toString(),
    );
  }
}
