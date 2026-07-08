import '../utils/ra_utils.dart';
import 'database_game_model.dart';

class RetroAchievementRecentUnlockItem {
  final String date;
  final bool hardcoreMode;
  final int achievementId;
  final String title;
  final String description;
  final String badgeName;
  final String badgeUrl;
  final int points;
  final int trueRatio;
  final String? type;
  final String author;
  final String authorUlid;
  final String gameTitle;
  final String gameIcon;
  final int gameId;
  final String consoleName;
  final String gameUrl;

  const RetroAchievementRecentUnlockItem({
    required this.date,
    required this.hardcoreMode,
    required this.achievementId,
    required this.title,
    required this.description,
    required this.badgeName,
    required this.badgeUrl,
    required this.points,
    required this.trueRatio,
    required this.type,
    required this.author,
    required this.authorUlid,
    required this.gameTitle,
    required this.gameIcon,
    required this.gameId,
    required this.consoleName,
    required this.gameUrl,
  });

  factory RetroAchievementRecentUnlockItem.fromJson(Map<String, dynamic> json) {
    return RetroAchievementRecentUnlockItem(
      date: (json['Date'] ?? json['date'] ?? '').toString(),
      hardcoreMode: RAParsingUtils.toBool(
        json['HardcoreMode'] ?? json['hardcoreMode'],
      ),
      achievementId: RAParsingUtils.toInt(
        json['AchievementID'] ?? json['achievementId'],
      ),
      title: (json['Title'] ?? json['title'] ?? '').toString(),
      description: (json['Description'] ?? json['description'] ?? '')
          .toString(),
      badgeName: (json['BadgeName'] ?? json['badgeName'] ?? '').toString(),
      badgeUrl: (json['BadgeURL'] ?? json['badgeUrl'] ?? '').toString(),
      points: RAParsingUtils.toInt(json['Points'] ?? json['points']),
      trueRatio: RAParsingUtils.toInt(json['TrueRatio'] ?? json['trueRatio']),
      type: (json['Type'] ?? json['type'])?.toString(),
      author: (json['Author'] ?? json['author'] ?? '').toString(),
      authorUlid: (json['AuthorULID'] ?? json['authorUlid'] ?? '').toString(),
      gameTitle: (json['GameTitle'] ?? json['gameTitle'] ?? '').toString(),
      gameIcon: (json['GameIcon'] ?? json['gameIcon'] ?? '').toString(),
      gameId: RAParsingUtils.toInt(json['GameID'] ?? json['gameId']),
      consoleName: (json['ConsoleName'] ?? json['consoleName'] ?? '')
          .toString(),
      gameUrl: (json['GameURL'] ?? json['gameUrl'] ?? '').toString(),
    );
  }
}

class RetroAchievementRecentlyPlayedGameItem {
  final int gameId;
  final int consoleId;
  final String consoleName;
  final String title;
  final String imageIcon;
  final String imageTitle;
  final String imageIngame;
  final String imageBoxArt;
  final String lastPlayed;
  final int achievementsTotal;
  final int numPossibleAchievements;
  final int possibleScore;
  final int numAchieved;
  final int scoreAchieved;
  final int numAchievedHardcore;
  final int scoreAchievedHardcore;

  const RetroAchievementRecentlyPlayedGameItem({
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
    required this.numPossibleAchievements,
    required this.possibleScore,
    required this.numAchieved,
    required this.scoreAchieved,
    required this.numAchievedHardcore,
    required this.scoreAchievedHardcore,
  });

  factory RetroAchievementRecentlyPlayedGameItem.fromJson(
    Map<String, dynamic> json,
  ) {
    return RetroAchievementRecentlyPlayedGameItem(
      gameId: RAParsingUtils.toInt(json['GameID'] ?? json['gameId']),
      consoleId: RAParsingUtils.toInt(json['ConsoleID'] ?? json['consoleId']),
      consoleName: (json['ConsoleName'] ?? json['consoleName'] ?? '')
          .toString(),
      title: (json['Title'] ?? json['title'] ?? '').toString(),
      imageIcon: (json['ImageIcon'] ?? json['imageIcon'] ?? '').toString(),
      imageTitle: (json['ImageTitle'] ?? json['imageTitle'] ?? '').toString(),
      imageIngame: (json['ImageIngame'] ?? json['imageIngame'] ?? '')
          .toString(),
      imageBoxArt: (json['ImageBoxArt'] ?? json['imageBoxArt'] ?? '')
          .toString(),
      lastPlayed: (json['LastPlayed'] ?? json['lastPlayed'] ?? '').toString(),
      achievementsTotal: RAParsingUtils.toInt(
        json['AchievementsTotal'] ?? json['achievementsTotal'],
      ),
      numPossibleAchievements: RAParsingUtils.toInt(
        json['NumPossibleAchievements'] ?? json['numPossibleAchievements'],
      ),
      possibleScore: RAParsingUtils.toInt(
        json['PossibleScore'] ?? json['possibleScore'],
      ),
      numAchieved: RAParsingUtils.toInt(
        json['NumAchieved'] ?? json['numAchieved'],
      ),
      scoreAchieved: RAParsingUtils.toInt(
        json['ScoreAchieved'] ?? json['scoreAchieved'],
      ),
      numAchievedHardcore: RAParsingUtils.toInt(
        json['NumAchievedHardcore'] ?? json['numAchievedHardcore'],
      ),
      scoreAchievedHardcore: RAParsingUtils.toInt(
        json['ScoreAchievedHardcore'] ?? json['scoreAchievedHardcore'],
      ),
    );
  }
}

class RetroAchievementCompletionProgressSummary {
  final int count;
  final int total;
  final List<RetroAchievementCompletionProgressItem> results;

  const RetroAchievementCompletionProgressSummary({
    required this.count,
    required this.total,
    required this.results,
  });

  factory RetroAchievementCompletionProgressSummary.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawResults =
        (json['Results'] as List<dynamic>?) ??
        (json['results'] as List<dynamic>?) ??
        const <dynamic>[];
    final results = rawResults
        .map(
          (item) => RetroAchievementCompletionProgressItem.fromJson(
            Map<String, dynamic>.from(item as Map),
          ),
        )
        .toList();
    return RetroAchievementCompletionProgressSummary(
      count: RAParsingUtils.toInt(json['Count'] ?? json['count']),
      total: RAParsingUtils.toInt(json['Total'] ?? json['total']),
      results: results,
    );
  }
}

class RetroAchievementCompletionProgressItem {
  final int gameId;
  final String title;
  final String imageIcon;
  final int consoleId;
  final String consoleName;
  final int maxPossible;
  final int numAwarded;
  final int numAwardedHardcore;
  final String mostRecentAwardedDate;
  final String highestAwardKind;
  final String highestAwardDate;

  const RetroAchievementCompletionProgressItem({
    required this.gameId,
    required this.title,
    required this.imageIcon,
    required this.consoleId,
    required this.consoleName,
    required this.maxPossible,
    required this.numAwarded,
    required this.numAwardedHardcore,
    required this.mostRecentAwardedDate,
    required this.highestAwardKind,
    required this.highestAwardDate,
  });

  factory RetroAchievementCompletionProgressItem.fromJson(
    Map<String, dynamic> json,
  ) {
    return RetroAchievementCompletionProgressItem(
      gameId: RAParsingUtils.toInt(json['GameID'] ?? json['gameId']),
      title: (json['Title'] ?? json['title'] ?? '').toString(),
      imageIcon: (json['ImageIcon'] ?? json['imageIcon'] ?? '').toString(),
      consoleId: RAParsingUtils.toInt(json['ConsoleID'] ?? json['consoleId']),
      consoleName: (json['ConsoleName'] ?? json['consoleName'] ?? '')
          .toString(),
      maxPossible: RAParsingUtils.toInt(
        json['MaxPossible'] ?? json['maxPossible'],
      ),
      numAwarded: RAParsingUtils.toInt(
        json['NumAwarded'] ?? json['numAwarded'],
      ),
      numAwardedHardcore: RAParsingUtils.toInt(
        json['NumAwardedHardcore'] ?? json['numAwardedHardcore'],
      ),
      mostRecentAwardedDate:
          (json['MostRecentAwardedDate'] ?? json['mostRecentAwardedDate'] ?? '')
              .toString(),
      highestAwardKind:
          (json['HighestAwardKind'] ?? json['highestAwardKind'] ?? '')
              .toString(),
      highestAwardDate:
          (json['HighestAwardDate'] ?? json['highestAwardDate'] ?? '')
              .toString(),
    );
  }
}

class OwnedWeekGameResolution {
  final int raGameId;
  final DatabaseGameModel game;

  const OwnedWeekGameResolution({required this.raGameId, required this.game});
}
