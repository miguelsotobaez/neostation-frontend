import '../utils/ra_utils.dart';

/// Aggregated model representing all awards earned by a user on RetroAchievements.org.
///
/// Includes counts for different award categories (Mastery, Completion, Beaten)
/// and a list of visible achievements/badges.
class RetroAchievementsUserAwards {
  /// Total number of awards earned by the user.
  final int totalAwardsCount;

  /// Number of awards that are currently hidden from public view.
  final int hiddenAwardsCount;

  /// Number of "Mastery" awards (completing all achievements in hardcore mode).
  final int masteryAwardsCount;

  /// Number of "Completion" awards (completing all achievements in casual mode).
  final int completionAwardsCount;

  /// Number of games "Beaten" in hardcore mode.
  final int beatenHardcoreAwardsCount;

  /// Number of games "Beaten" in casual mode.
  final int beatenCasualAwardsCount;

  /// Number of awards earned during special community events.
  final int eventAwardsCount;

  /// Number of site-wide awards (e.g., anniversary badges).
  final int siteAwardsCount;

  /// List of award details currently visible on the user's profile.
  final List<UserAward> visibleUserAwards;

  RetroAchievementsUserAwards({
    required this.totalAwardsCount,
    required this.hiddenAwardsCount,
    required this.masteryAwardsCount,
    required this.completionAwardsCount,
    required this.beatenHardcoreAwardsCount,
    required this.beatenCasualAwardsCount,
    required this.eventAwardsCount,
    required this.siteAwardsCount,
    required this.visibleUserAwards,
  });

  /// Creates a [RetroAchievementsUserAwards] instance from a JSON-compatible map provided by the RA API.
  factory RetroAchievementsUserAwards.fromJson(Map<String, dynamic> json) {
    return RetroAchievementsUserAwards(
      totalAwardsCount: RAParsingUtils.toInt(json['TotalAwardsCount']),
      hiddenAwardsCount: RAParsingUtils.toInt(json['HiddenAwardsCount']),
      masteryAwardsCount: RAParsingUtils.toInt(json['MasteryAwardsCount']),
      completionAwardsCount: RAParsingUtils.toInt(
        json['CompletionAwardsCount'],
      ),
      beatenHardcoreAwardsCount: RAParsingUtils.toInt(
        json['BeatenHardcoreAwardsCount'],
      ),
      beatenCasualAwardsCount: RAParsingUtils.toInt(
        json['BeatenSoftcoreAwardsCount'],
      ),
      eventAwardsCount: RAParsingUtils.toInt(json['EventAwardsCount']),
      siteAwardsCount: RAParsingUtils.toInt(json['SiteAwardsCount']),
      visibleUserAwards: (json['VisibleUserAwards'] as List<dynamic>? ?? [])
          .map((e) => UserAward.fromJson(e))
          .toList(),
    );
  }
}

/// Represents a specific award or badge earned by a user.
class UserAward {
  /// Timestamp when the award was granted.
  final String awardedAt;

  /// Title of the game or event associated with the award.
  final String title;

  /// Internal platform identifier (e.g., 1 for NES).
  final int consoleId;

  /// Human-readable name of the console platform.
  final String consoleName;

  /// Internal status or metadata flags.
  final String? flags;

  /// Path to the award's icon image.
  final String imageIcon;

  /// Category classification of the award (e.g., 'Mastery').
  final String awardType;

  /// Primary data value associated with the award (typically the Game ID).
  final int awardData;

  /// Secondary data value associated with the award.
  final int awardDataExtra;

  /// Numerical value determining the display order of the award.
  final int displayOrder;

  UserAward({
    required this.awardedAt,
    required this.title,
    required this.consoleId,
    required this.consoleName,
    this.flags,
    required this.imageIcon,
    required this.awardType,
    required this.awardData,
    required this.awardDataExtra,
    required this.displayOrder,
  });

  /// Creates a [UserAward] instance from a JSON-compatible map.
  factory UserAward.fromJson(Map<String, dynamic> json) {
    return UserAward(
      awardedAt: (json['AwardedAt'] ?? '').toString(),
      title: (json['Title'] ?? '').toString(),
      consoleId: RAParsingUtils.toInt(json['ConsoleID']),
      consoleName: (json['ConsoleName'] ?? '').toString(),
      flags: json['Flags']?.toString(),
      imageIcon: (json['ImageIcon'] ?? '').toString(),
      awardType: (json['AwardType'] ?? '').toString(),
      awardData: RAParsingUtils.toInt(json['AwardData']),
      awardDataExtra: RAParsingUtils.toInt(json['AwardDataExtra']),
      displayOrder: RAParsingUtils.toInt(json['DisplayOrder']),
    );
  }
}
