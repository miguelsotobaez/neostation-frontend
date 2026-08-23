/// A game in the bundled RetroAchievements snapshot (`app_ra_game_list`).
///
/// The table stores one row per registered hash, so several rows can describe
/// the same game; this model is the de-duplicated, game-level view used when
/// the user picks a match by hand.
class RaGameListEntry {
  /// RetroAchievements game id.
  final int gameId;

  /// Title as RetroAchievements publishes it, including `[Subset - …]` and
  /// `~Hack~` markers.
  final String title;

  /// Number of achievements in the set, when the snapshot recorded it.
  final int? numAchievements;

  /// Total points available in the set, when the snapshot recorded it.
  final int? points;

  const RaGameListEntry({
    required this.gameId,
    required this.title,
    this.numAchievements,
    this.points,
  });

  factory RaGameListEntry.fromRow(Map<String, dynamic> row) => RaGameListEntry(
    gameId: int.tryParse(row['game_id']?.toString() ?? '') ?? 0,
    title: row['title']?.toString() ?? '',
    numAchievements: int.tryParse(row['num_achievements']?.toString() ?? ''),
    points: int.tryParse(row['points']?.toString() ?? ''),
  );

  /// Whether this entry is a subset rather than a main achievement set.
  bool get isSubset => title.contains('[Subset');

  /// Whether this entry describes a ROM hack rather than the original game.
  bool get isHack => title.startsWith('~Hack~');
}
