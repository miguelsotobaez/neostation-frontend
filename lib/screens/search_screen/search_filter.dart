import 'package:neostation/models/database_game_model.dart';

/// Pure search / filter logic backing the library-wide [SearchScreen].
///
/// Kept free of Flutter and widget state so it can be unit-tested directly:
/// the screen owns presentation and gamepad focus, these functions own the
/// in-memory matching, sorting and option-derivation rules.

/// Discrete rating thresholds the rating filter can offer, ascending. The
/// "Any" slot is added by the facet, so it is not part of this list.
const List<double> kRatingThresholds = [3.0, 4.0, 4.5];

/// Keys identifying a filter dimension, shared by the criteria, the facet sets
/// and the screen's chip row.
const String kFilterPlatform = 'platform';
const String kFilterDeveloper = 'developer';
const String kFilterGenre = 'genre';
const String kFilterYear = 'year';
const String kFilterRating = 'rating';

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

  /// This selection with [dimension] reset to "Any".
  ///
  /// Facets are derived per dimension from everything *except* that dimension,
  /// so a filter's own choice never narrows the options it offers.
  SearchCriteria without(String dimension) => SearchCriteria(
    query: query,
    platform: dimension == kFilterPlatform ? null : platform,
    developer: dimension == kFilterDeveloper ? null : developer,
    genre: dimension == kFilterGenre ? null : genre,
    year: dimension == kFilterYear ? null : year,
    minRating: dimension == kFilterRating ? null : minRating,
  );

  /// The active value for a string-valued [dimension] (null == Any).
  String? valueOf(String dimension) => switch (dimension) {
    kFilterPlatform => platform,
    kFilterDeveloper => developer,
    kFilterGenre => genre,
    kFilterYear => year,
    _ => null,
  };
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

/// Whether [g] satisfies every dimension of [criteria].
bool matchesCriteria(DatabaseGameModel g, SearchCriteria criteria) {
  final query = criteria.query.trim().toLowerCase();
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
  final minRating = criteria.minRating;
  if (minRating != null && (g.rating ?? -1) < minRating) return false;
  return true;
}

/// Applies [criteria] to [games] and returns the matches sorted by display
/// name (realName, falling back to filename), case-insensitively.
List<DatabaseGameModel> filterAndSortGames(
  Iterable<DatabaseGameModel> games,
  SearchCriteria criteria,
) {
  return games.where((g) => matchesCriteria(g, criteria)).toList()
    ..sort((a, b) {
      final an = (a.realName ?? a.filename).toLowerCase();
      final bn = (b.realName ?? b.filename).toLowerCase();
      return an.compareTo(bn);
    });
}

/// The option sets offered by the filter chips for a given selection.
///
/// Each list is derived from the games that match every *other* dimension, so
/// the filters only ever offer values that can actually narrow the current
/// results — searching "Sonic" leaves no NES entry in the platform picker.
class SearchFacets {
  const SearchFacets({
    this.platforms = const [],
    this.developers = const [],
    this.genres = const [],
    this.years = const [],
    this.ratings = const [],
  });

  final List<String> platforms;
  final List<String> developers;
  final List<String> genres;
  final List<String> years;

  /// Rating thresholds that at least one candidate game reaches.
  final List<double> ratings;

  static const SearchFacets empty = SearchFacets();

  /// String options for a dimension ([kFilterRating] has its own list).
  List<String> optionsFor(String dimension) => switch (dimension) {
    kFilterPlatform => platforms,
    kFilterDeveloper => developers,
    kFilterGenre => genres,
    kFilterYear => years,
    _ => const [],
  };
}

/// Derives the per-dimension filter options available under [criteria].
SearchFacets computeFacets(
  Iterable<DatabaseGameModel> games,
  SearchCriteria criteria,
) {
  final all = games is List<DatabaseGameModel> ? games : games.toList();
  return SearchFacets(
    platforms: _facet(all, criteria, kFilterPlatform, (g) => g.systemRealName),
    developers: _facet(all, criteria, kFilterDeveloper, (g) => g.developer),
    genres: _facet(all, criteria, kFilterGenre, (g) => g.genre),
    years: _yearFacet(all, criteria),
    ratings: _ratingFacet(all, criteria),
  );
}

/// Candidate games for [dimension]'s facet: everything matching the other
/// dimensions of [criteria].
Iterable<DatabaseGameModel> _candidates(
  List<DatabaseGameModel> games,
  SearchCriteria criteria,
  String dimension,
) {
  final scoped = criteria.without(dimension);
  return games.where((g) => matchesCriteria(g, scoped));
}

/// Options for a string-valued dimension.
///
/// An active value is kept in the list even when nothing matches it any more
/// (a query that strands the current selection), so the chip stays consistent
/// with its picker and the user can still cycle off it.
List<String> _facet(
  List<DatabaseGameModel> games,
  SearchCriteria criteria,
  String dimension,
  String? Function(DatabaseGameModel) pick,
) {
  final options = distinctOptions(
    _candidates(games, criteria, dimension),
    pick,
  );
  final active = criteria.valueOf(dimension);
  if (active != null && !options.contains(active)) {
    options
      ..add(active)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }
  return options;
}

List<String> _yearFacet(
  List<DatabaseGameModel> games,
  SearchCriteria criteria,
) {
  final years = distinctYears(_candidates(games, criteria, kFilterYear));
  final active = criteria.year;
  if (active != null && !years.contains(active)) {
    years
      ..add(active)
      ..sort((a, b) => b.compareTo(a));
  }
  return years;
}

/// Thresholds reachable by the candidate set. Thresholds are monotonic, so the
/// best rating on offer decides how many of them are worth showing.
List<double> _ratingFacet(
  List<DatabaseGameModel> games,
  SearchCriteria criteria,
) {
  var best = -1.0;
  for (final g in _candidates(games, criteria, kFilterRating)) {
    final r = g.rating;
    if (r != null && r > best) best = r;
  }
  final thresholds = kRatingThresholds.where((t) => t <= best).toList();
  final active = criteria.minRating;
  if (active != null && !thresholds.contains(active)) {
    thresholds
      ..add(active)
      ..sort();
  }
  return thresholds;
}

/// Cycles through [options] with an "Any" (null) slot at the head, moving by
/// [delta] with wraparound. Returns the newly selected value (null == Any).
T? cycleFilterValue<T>(List<T> options, T? current, int delta) {
  final len = options.length + 1;
  final currentIdx = current == null ? 0 : options.indexOf(current) + 1;
  var next = (currentIdx + delta) % len;
  if (next < 0) next += len;
  return next == 0 ? null : options[next - 1];
}
