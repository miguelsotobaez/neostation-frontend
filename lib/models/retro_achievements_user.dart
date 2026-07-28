import '../utils/ra_utils.dart';

/// Represents a user profile from RetroAchievements.org.
///
/// Contains core account details, cumulative scores across both casual and
/// hardcore modes, and social information like motto and user picture.
class RetroAchievementsUser {
  /// Username of the player.
  final String user;

  /// Unique internal identifier string (ULID).
  final String ulid;

  /// Relative path to the user's profile picture image.
  final String userPic;

  /// Timestamp indicating when the user account was created.
  final String memberSince;

  /// Current "Rich Presence" status message showing live game activity.
  final String richPresenceMsg;

  /// Unique identifier of the last game launched by the user.
  final int lastGameId;

  /// Total count of developer contributions to the community.
  final int contribCount;

  /// Total contribution yield points awarded for development work.
  final int contribYield;

  /// Total points accumulated (Hardcore mode).
  final int totalPoints;

  /// Total points accumulated in casual mode.
  final int totalCasualPoints;

  /// Total weighted "True" points based on achievement rarity.
  final int totalTruePoints;

  /// Numerical permission level for administrative or development roles.
  final int permissions;

  /// Number of achievements earned in untracked or unofficial games.
  final int untracked;

  /// Unique internal numerical user identifier.
  final int id;

  /// Whether the user's profile wall is currently active.
  final bool userWallActive;

  /// User's custom status or biographical motto.
  final String motto;

  RetroAchievementsUser({
    required this.user,
    required this.ulid,
    required this.userPic,
    required this.memberSince,
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
  });

  /// Creates a [RetroAchievementsUser] instance from a JSON-compatible map provided by the RA API.
  factory RetroAchievementsUser.fromJson(Map<String, dynamic> json) {
    return RetroAchievementsUser(
      user: (json['User'] ?? '').toString(),
      ulid: (json['ULID'] ?? '').toString(),
      userPic: (json['UserPic'] ?? '').toString(),
      memberSince: (json['MemberSince'] ?? '').toString(),
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
    );
  }

  /// Whether the user primarily or exclusively plays in casual mode.
  bool get isCasual => totalCasualPoints > totalPoints;

  /// Returns a display string representing the user's primary gameplay mode.
  String get userType => isCasual ? 'Casual User' : 'Hardcore User';
}
