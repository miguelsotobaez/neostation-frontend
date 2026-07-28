import 'package:flutter_test/flutter_test.dart';

import 'package:neostation/models/database_game_model.dart';
import 'package:neostation/screens/search_screen/search_filter.dart';

/// Builds a minimal [DatabaseGameModel] for filter tests; only the fields the
/// search logic reads need values.
DatabaseGameModel game({
  String? realName,
  String filename = 'rom.zip',
  String? systemRealName,
  String? developer,
  String? genre,
  String? year,
  double? rating,
}) {
  return DatabaseGameModel(
    filename: filename,
    romPath: '/roms/$filename',
    realName: realName,
    systemRealName: systemRealName,
    developer: developer,
    genre: genre,
    year: year,
    rating: rating,
  );
}

void main() {
  group('searchYearOf', () {
    test('extracts a 4-digit year from a plain year string', () {
      expect(searchYearOf(game(year: '1998')), '1998');
    });

    test('extracts the year from an ISO release-date string', () {
      expect(searchYearOf(game(year: '1998-09-23')), '1998');
    });

    test('returns null for null, empty, or yearless values', () {
      expect(searchYearOf(game(year: null)), isNull);
      expect(searchYearOf(game(year: '   ')), isNull);
      expect(searchYearOf(game(year: 'unknown')), isNull);
    });
  });

  group('distinctOptions', () {
    test('dedupes, trims whitespace and sorts case-insensitively', () {
      final games = [
        game(developer: 'Konami'),
        game(developer: ' Konami '), // trimmed → dupe of 'Konami'
        game(developer: 'capcom'),
        game(developer: 'Atari'),
        game(developer: ''),
        game(developer: null),
      ];
      // Sort is case-insensitive: atari, capcom, konami.
      expect(distinctOptions(games, (g) => g.developer), [
        'Atari',
        'capcom',
        'Konami',
      ]);
    });
  });

  group('distinctYears', () {
    test('collects distinct years sorted newest first', () {
      final games = [
        game(year: '1990'),
        game(year: '2003-01-01'),
        game(year: '1990'),
        game(year: 'n/a'),
      ];
      expect(distinctYears(games), ['2003', '1990']);
    });
  });

  group('filterAndSortGames', () {
    final library = [
      game(
        realName: 'Zelda',
        systemRealName: 'NES',
        genre: 'Adventure',
        rating: 4.8,
      ),
      game(
        realName: 'Mario',
        systemRealName: 'NES',
        genre: 'Platformer',
        rating: 4.5,
      ),
      game(
        realName: 'Sonic',
        systemRealName: 'Genesis',
        genre: 'Platformer',
        rating: 3.0,
      ),
    ];

    test('empty criteria returns everything sorted by display name', () {
      final r = filterAndSortGames(library, const SearchCriteria());
      expect(r.map((g) => g.realName), ['Mario', 'Sonic', 'Zelda']);
    });

    test('name query matches case-insensitively against realName', () {
      final r = filterAndSortGames(library, const SearchCriteria(query: 'mar'));
      expect(r.map((g) => g.realName), ['Mario']);
    });

    test('falls back to filename when realName is null', () {
      final games = [game(filename: 'Tetris.zip')];
      final r = filterAndSortGames(
        games,
        const SearchCriteria(query: 'tetris'),
      );
      expect(r, hasLength(1));
    });

    test('platform filter matches systemRealName exactly', () {
      final r = filterAndSortGames(
        library,
        const SearchCriteria(platform: 'Genesis'),
      );
      expect(r.map((g) => g.realName), ['Sonic']);
    });

    test('genre filter narrows results', () {
      final r = filterAndSortGames(
        library,
        const SearchCriteria(genre: 'Platformer'),
      );
      expect(r.map((g) => g.realName), ['Mario', 'Sonic']);
    });

    test('minRating excludes lower-rated and unrated games', () {
      final games = [...library, game(realName: 'NoRating', rating: null)];
      final r = filterAndSortGames(games, const SearchCriteria(minRating: 4.0));
      expect(r.map((g) => g.realName), ['Mario', 'Zelda']);
    });

    test('combines multiple criteria with AND semantics', () {
      final r = filterAndSortGames(
        library,
        const SearchCriteria(platform: 'NES', genre: 'Platformer'),
      );
      expect(r.map((g) => g.realName), ['Mario']);
    });

    test('returns empty when nothing matches', () {
      final r = filterAndSortGames(
        library,
        const SearchCriteria(query: 'doesnotexist'),
      );
      expect(r, isEmpty);
    });
  });

  group('computeFacets', () {
    final library = [
      game(
        realName: 'Sonic the Hedgehog',
        systemRealName: 'Genesis',
        developer: 'Sega',
        genre: 'Platformer',
        year: '1991',
        rating: 4.6,
      ),
      game(
        realName: 'Sonic CD',
        systemRealName: 'Sega CD',
        developer: 'Sega',
        genre: 'Platformer',
        year: '1993',
        rating: 4.2,
      ),
      game(
        realName: 'Super Mario Bros',
        systemRealName: 'NES',
        developer: 'Nintendo',
        genre: 'Platformer',
        year: '1985',
        rating: 4.9,
      ),
      game(
        realName: 'Contra',
        systemRealName: 'NES',
        developer: 'Konami',
        genre: 'Shooter',
        year: '1988',
        rating: 3.5,
      ),
    ];

    test('a name query drops platforms with no matching game', () {
      final f = computeFacets(library, const SearchCriteria(query: 'sonic'));
      expect(f.platforms, ['Genesis', 'Sega CD']);
      expect(f.developers, ['Sega']);
      expect(f.genres, ['Platformer']);
      expect(f.years, ['1993', '1991']);
    });

    test('a filter does not narrow its own options', () {
      // Platform is pinned, so the platform picker still offers every platform
      // the query allows — otherwise the user could never switch away.
      final f = computeFacets(
        library,
        const SearchCriteria(query: 'sonic', platform: 'Genesis'),
      );
      expect(f.platforms, ['Genesis', 'Sega CD']);
      // Other dimensions do see the pinned platform.
      expect(f.years, ['1991']);
    });

    test('other active filters narrow a dimension', () {
      final f = computeFacets(library, const SearchCriteria(genre: 'Shooter'));
      expect(f.platforms, ['NES']);
      expect(f.developers, ['Konami']);
    });

    test('rating thresholds stop at the best rating on offer', () {
      final f = computeFacets(library, const SearchCriteria(query: 'contra'));
      expect(f.ratings, [3.0]);
      final all = computeFacets(library, const SearchCriteria());
      expect(all.ratings, [3.0, 4.0, 4.5]);
    });

    test('a stranded active value stays selectable', () {
      // Nothing named Sonic is on the NES, but the chip has to keep showing
      // (and offering) the value it is filtering by.
      final f = computeFacets(
        library,
        const SearchCriteria(query: 'sonic', platform: 'NES'),
      );
      expect(f.platforms, contains('NES'));
      expect(
        filterAndSortGames(
          library,
          const SearchCriteria(query: 'sonic', platform: 'NES'),
        ),
        isEmpty,
      );
    });

    test('empty results leave every facet empty', () {
      final f = computeFacets(
        library,
        const SearchCriteria(query: 'doesnotexist'),
      );
      expect(f.platforms, isEmpty);
      expect(f.developers, isEmpty);
      expect(f.genres, isEmpty);
      expect(f.years, isEmpty);
      expect(f.ratings, isEmpty);
    });
  });

  group('cycleFilterValue', () {
    final options = ['A', 'B', 'C'];

    test('starts at Any (null) and advances forward', () {
      expect(cycleFilterValue(options, null, 1), 'A');
      expect(cycleFilterValue(options, 'A', 1), 'B');
      expect(cycleFilterValue(options, 'C', 1), isNull); // wraps to Any
    });

    test('moves backward with wraparound through the Any slot', () {
      expect(cycleFilterValue(options, null, -1), 'C');
      expect(cycleFilterValue(options, 'A', -1), isNull);
    });

    test('treats an unknown current value as Any', () {
      // indexOf returns -1, so currentIdx is 0 (the Any slot).
      expect(cycleFilterValue(options, 'X', 1), 'A');
    });
  });
}
