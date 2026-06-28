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
      expect(
        distinctOptions(games, (g) => g.developer),
        ['Atari', 'capcom', 'Konami'],
      );
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
      game(realName: 'Zelda', systemRealName: 'NES', genre: 'Adventure', rating: 4.8),
      game(realName: 'Mario', systemRealName: 'NES', genre: 'Platformer', rating: 4.5),
      game(realName: 'Sonic', systemRealName: 'Genesis', genre: 'Platformer', rating: 3.0),
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
      final r =
          filterAndSortGames(library, const SearchCriteria(platform: 'Genesis'));
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
      final r =
          filterAndSortGames(games, const SearchCriteria(minRating: 4.0));
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
