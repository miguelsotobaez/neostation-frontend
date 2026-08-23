import 'package:neostation/models/romm_rom.dart';

/// One page of `/api/roms` results plus the envelope RomM wraps them in.
///
/// RomM answers a filtered query with more than the rows themselves: [total] is
/// the exact number of matches across the whole library (not just this page),
/// and [filterValues] lists the values each filter dimension can still take for
/// that query — the server-side equivalent of the local faceting.
class RommRomPage {
  const RommRomPage({
    required this.items,
    this.total = 0,
    this.filterValues = const {},
  });

  final List<RommRom> items;

  /// Matches across the whole library, so a UI can say "310 results" rather
  /// than counting the rows it happens to have paged in.
  final int total;

  /// Available values per dimension (`genres`, `companies`, `franchises`, …),
  /// scoped to the query that produced this page. `platforms` is a list of
  /// RomM platform ids rather than names and is left out here.
  final Map<String, List<String>> filterValues;

  /// Values offered for [dimension], or empty when RomM sent none.
  List<String> valuesFor(String dimension) =>
      filterValues[dimension] ?? const [];
}
