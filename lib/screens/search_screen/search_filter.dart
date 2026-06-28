import 'package:neostation/models/database_game_model.dart';

/// Pure search / filter logic backing the library-wide [SearchScreen].
///
/// Kept free of Flutter and widget state so it can be unit-tested directly:
/// the screen owns presentation and gamepad focus, these functions own the
/// in-memory matching, sorting and option-derivation rules.

/// Discrete rating thresholds offered in the rating filter (null == Any).
const List<double?> kRatingThresholds = [null, 3.0, 4.0, 4.5];

/// Active filter selection. A null field means "Any" for that dimension.
class SearchCriteria {
  const SearchCriteria({
    this.query = '',
    this.platform,
    this.developer,
    this.genre,
    this.year,
    this.minRating,
  });

  final String query;
  final String? platform;
  final String? developer;
  final String? genre;
  final String? year;
  final double? minRating;
}

/// Extracts a 4-digit year from a raw year / ISO release-date string.
String? searchYearOf(DatabaseGameModel g) {
  final raw = g.year?.trim();
  if (raw == null || raw.isEmpty) return null;
  final m = RegExp(r'(\d{4})').firstMatch(raw);
  return m?.group(1);
}

/// Distinct, case-insensitively sorted, non-empty values produced by [pick].
List<String> distinctOptions(
  Iterable<DatabaseGameModel> games,
  String? Function(DatabaseGameModel) pick,
) {
  final set = <String>{};
  for (final g in games) {
    final v = pick(g)?.trim();
    if (v != null && v.isNotEmpty) set.add(v);
  }
  return set.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
}

/// Distinct 4-digit years present in [games], sorted newest first.
List<String> distinctYears(Iterable<DatabaseGameModel> games) {
  final set = <String>{};
  for (final g in games) {
    final y = searchYearOf(g);
    if (y != null) set.add(y);
  }
  return set.toList()..sort((a, b) => b.compareTo(a));
}

/// Applies [criteria] to [games] and returns the matches sorted by display
/// name (realName, falling back to filename), case-insensitively.
List<DatabaseGameModel> filterAndSortGames(
  Iterable<DatabaseGameModel> games,
  SearchCriteria criteria,
) {
  final query = criteria.query.trim().toLowerCase();
  final minRating = criteria.minRating;

  return games.where((g) {
    if (query.isNotEmpty) {
      final name = (g.realName ?? g.filename).toLowerCase();
      if (!name.contains(query)) return false;
    }
    if (criteria.platform != null && g.systemRealName != criteria.platform) {
      return false;
    }
    if (criteria.developer != null &&
        (g.developer?.trim() ?? '') != criteria.developer) {
      return false;
    }
    if (criteria.genre != null && (g.genre?.trim() ?? '') != criteria.genre) {
      return false;
    }
    if (criteria.year != null && searchYearOf(g) != criteria.year) return false;
    if (minRating != null && (g.rating ?? -1) < minRating) return false;
    return true;
  }).toList()..sort((a, b) {
    final an = (a.realName ?? a.filename).toLowerCase();
    final bn = (b.realName ?? b.filename).toLowerCase();
    return an.compareTo(bn);
  });
}

/// Cycles through [options] with an "Any" (null) slot at the head, moving by
/// [delta] with wraparound. Returns the newly selected value (null == Any).
String? cycleFilterValue(List<String> options, String? current, int delta) {
  final len = options.length + 1;
  final currentIdx = current == null ? 0 : options.indexOf(current) + 1;
  var next = (currentIdx + delta) % len;
  if (next < 0) next += len;
  return next == 0 ? null : options[next - 1];
}
