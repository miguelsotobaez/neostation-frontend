/// Persisted values for `ConfigModel.recentCardSize` — the cell span the
/// "Recently Played" card takes in the systems grid.
///
/// The label shown next to each value lives in `AppLocale`; these are the raw
/// strings written to `user_config.recent_card_size`.
class RecentCardSizes {
  /// The 3x2 block the card has used since it was introduced.
  static const String defaultSize = 'default';

  /// A compact card two columns wide and one row tall.
  static const String twoByOne = '2x1';
}
