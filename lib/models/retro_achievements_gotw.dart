/// Represents the "Game of the Week" data from RetroAchievements.org.
class RetroAchievementsGOTW {
  /// The specific achievement featured for the week.
  final Achievement achievement;

  /// The console platform for the featured game.
  final Console console;

  /// The featured game entry.
  final Game game;

  /// The start date/time of the event.
  final String startAt;

  /// Total number of unique players participating in the event.
  final int totalPlayers;

  /// List of recent unlocks by users during the event.
  final List<Unlock> unlocks;

  /// Total count of unlocks in casual mode.
  final int unlocksCount;

  /// Total count of unlocks in hardcore mode.
  final int unlocksHardcoreCount;

  RetroAchievementsGOTW({
    required this.achievement,
    required this.console,
    required this.game,
    required this.startAt,
    required this.totalPlayers,
    required this.unlocks,
    required this.unlocksCount,
    required this.unlocksHardcoreCount,
  });

  /// Creates a [RetroAchievementsGOTW] from a JSON-compatible map.
  factory RetroAchievementsGOTW.fromJson(Map<String, dynamic> json) {
    return RetroAchievementsGOTW(
      achievement: Achievement.fromJson(json['Achievement']),
      console: Console.fromJson(json['Console']),
      game: Game.fromJson(json['Game']),
      startAt: json['StartAt']?.toString() ?? '',
      totalPlayers: int.tryParse(json['TotalPlayers']?.toString() ?? '') ?? 0,
      unlocks:
          (json['Unlocks'] as List?)?.map((i) => Unlock.fromJson(i)).toList() ??
          [],
      unlocksCount: int.tryParse(json['UnlocksCount']?.toString() ?? '') ?? 0,
      unlocksHardcoreCount:
          int.tryParse(json['UnlocksHardcoreCount']?.toString() ?? '') ?? 0,
    );
  }
}

/// Simplified achievement model used within the GOTW data structure.
class Achievement {
  /// Unique identifier for the achievement.
  final int id;

  /// Display title of the achievement.
  final String title;

  /// Short description of the requirements.
  final String description;

  /// Point value.
  final int points;

  /// Weighted difficulty score.
  final int trueRatio;

  /// Category type (e.g., 'progression').
  final String type;

  /// Username of the author.
  final String author;

  /// Identifier for the badge icon.
  final String badgeName;

  /// Absolute URL to the badge icon image.
  final String badgeUrl;

  /// Timestamp when the achievement was created.
  final String dateCreated;

  /// Timestamp when the achievement was last modified.
  final String dateModified;

  Achievement({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
    required this.trueRatio,
    required this.type,
    required this.author,
    required this.badgeName,
    required this.badgeUrl,
    required this.dateCreated,
    required this.dateModified,
  });

  /// Creates an [Achievement] from a JSON-compatible map.
  factory Achievement.fromJson(Map<String, dynamic> json) {
    return Achievement(
      id: int.tryParse(json['ID']?.toString() ?? '') ?? 0,
      title: json['Title']?.toString() ?? '',
      description: json['Description']?.toString() ?? '',
      points: int.tryParse(json['Points']?.toString() ?? '') ?? 0,
      trueRatio: int.tryParse(json['TrueRatio']?.toString() ?? '') ?? 0,
      type: json['Type']?.toString() ?? '',
      author: json['Author']?.toString() ?? '',
      badgeName: json['BadgeName']?.toString() ?? '',
      badgeUrl: json['BadgeURL']?.toString() ?? '',
      dateCreated: json['DateCreated']?.toString() ?? '',
      dateModified: json['DateModified']?.toString() ?? '',
    );
  }
}

/// Simplified console model used within the GOTW data structure.
class Console {
  /// Unique console identifier.
  final int id;

  /// Full name of the platform.
  final String title;

  Console({required this.id, required this.title});

  /// Creates a [Console] from a JSON-compatible map.
  factory Console.fromJson(Map<String, dynamic> json) {
    return Console(
      id: int.tryParse(json['ID']?.toString() ?? '') ?? 0,
      title: json['Title']?.toString() ?? '',
    );
  }
}

/// Simplified game model used within the GOTW data structure.
class Game {
  /// Unique game identifier on RetroAchievements.org.
  final int id;

  /// Full title of the game.
  final String title;

  Game({required this.id, required this.title});

  /// Creates a [Game] from a JSON-compatible map.
  factory Game.fromJson(Map<String, dynamic> json) {
    return Game(
      id: int.tryParse(json['ID']?.toString() ?? '') ?? 0,
      title: json['Title']?.toString() ?? '',
    );
  }
}

/// Represents an achievement unlock event by a user during the GOTW.
class Unlock {
  /// Username of the player who earned the achievement.
  final String user;

  /// Hardcore points earned.
  final String raPoints;

  /// Casual points earned.
  final String raCasualPoints;

  /// Indicates if the unlock was in hardcore mode (1) or casual mode (0).
  final int hardcoreMode;

  /// Timestamp when the achievement was awarded.
  final String dateAwarded;

  Unlock({
    required this.user,
    required this.raPoints,
    required this.raCasualPoints,
    required this.hardcoreMode,
    required this.dateAwarded,
  });

  /// Creates an [Unlock] from a JSON-compatible map.
  factory Unlock.fromJson(Map<String, dynamic> json) {
    return Unlock(
      user: (json['User'] ?? '').toString(),
      raPoints: (json['RAPoints'] ?? '0').toString(),
      raCasualPoints: (json['RASoftcorePoints'] ?? '0').toString(),
      hardcoreMode: int.tryParse((json['HardcoreMode'] ?? '0').toString()) ?? 0,
      dateAwarded: (json['DateAwarded'] ?? '').toString(),
    );
  }
}
