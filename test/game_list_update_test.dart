import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/utils/game_list_update.dart';

GameModel game(String romname, String name) => GameModel(
  romname: romname,
  realname: name,
  name: name,
  year: '',
  developer: '',
  publisher: '',
  genre: '',
  players: '',
  rating: 0,
);

GameModel fav(String name) => GameModel(
  romname: '$name.nes',
  realname: name,
  name: name,
  year: '',
  developer: '',
  publisher: '',
  genre: '',
  players: '',
  rating: 0,
  isFavorite: true,
);

List<String> namesOf(List<GameModel> games) =>
    games.map((g) => g.name).toList();

void main() {
  test('replacing a scraped game publishes a new list identity', () {
    final original = [game('mario.nes', 'Mario'), game('zelda.nes', 'Zelda')];
    final updated = game('mario.nes', 'Super Mario Bros.');

    final result = replaceGameInList(original, updated);

    expect(identical(result, original), isFalse);
    expect(result, hasLength(2));
    expect(result[0], same(updated));
    expect(result[1], same(original[1]));
    expect(original[0].name, 'Mario');
  });

  test('an update for an unknown ROM leaves the list unchanged', () {
    final original = [game('mario.nes', 'Mario')];

    final result = replaceGameInList(original, game('zelda.nes', 'Zelda'));

    expect(result, same(original));
  });

  /// Un-marking a favourite moves the game; marking one does not.
  ///
  /// The asymmetry is the point. A game left stranded at the head of the list
  /// after losing its star made the carousel's alphabet bar raise a chip out of
  /// sequence — a `G` before `4` and `A` — plus a duplicate of its real letter
  /// further along that could never highlight, because the bar matches the
  /// first chip carrying a label.
  group('re-seating a game that has lost its star', () {
    test('it drops to its alphabetical place', () {
      final games = [
        game('gzero.nes', 'G-Zero'), // just un-starred, still at the front
        game('4wd.nes', '4WD'),
        game('alpha.nes', 'Alpha'),
        game('zulu.nes', 'Zulu'),
      ];

      final reseated = reseatUnfavoritedGame(games, 'gzero.nes');

      expect(namesOf(reseated), ['4WD', 'Alpha', 'G-Zero', 'Zulu']);
    });

    test('it lands after the favourites that remain', () {
      final games = [
        game('gzero.nes', 'G-Zero'),
        fav('Zulu'), // still starred: holds the front, out of name order
        game('alpha.nes', 'Alpha'),
      ];

      final reseated = reseatUnfavoritedGame(games, 'gzero.nes');

      expect(namesOf(reseated), ['Zulu', 'Alpha', 'G-Zero']);
    });

    test('favourites marked in place are not dragged to the top with it', () {
      // Why this is a splice and not a sort. Bravo was starred mid-browse and
      // deliberately left where it stood; un-starring G-Zero must not collect
      // it on the way past.
      final games = [
        game('gzero.nes', 'G-Zero'),
        game('alpha.nes', 'Alpha'),
        fav('Bravo'),
        game('charlie.nes', 'Charlie'),
      ];

      final reseated = reseatUnfavoritedGame(games, 'gzero.nes');

      expect(namesOf(reseated), ['Alpha', 'Bravo', 'Charlie', 'G-Zero']);
    });

    test('it stops short of an in-place favourite that outranks it', () {
      // The bug the leading-run rule exists for. Zulu was starred mid-browse
      // and kept its alphabetical seat at the end, so it is not part of the
      // block at the front — treating every flagged game as "sorts first"
      // skipped straight over it and parked G-Zero last.
      final games = [
        game('gzero.nes', 'G-Zero'),
        game('alpha.nes', 'Alpha'),
        game('charlie.nes', 'Charlie'),
        fav('Zulu'),
      ];

      final reseated = reseatUnfavoritedGame(games, 'gzero.nes');

      expect(namesOf(reseated), ['Alpha', 'Charlie', 'G-Zero', 'Zulu']);
    });

    test('a game already in its place keeps the list identity', () {
      final games = [
        game('alpha.nes', 'Alpha'),
        game('gzero.nes', 'G-Zero'),
        game('zulu.nes', 'Zulu'),
      ];

      expect(
        reseatUnfavoritedGame(games, 'gzero.nes'),
        same(games),
        reason: 'no move means no new list for the views to rebuild against',
      );
    });

    test('a game that is still a favourite does not move', () {
      final games = [fav('Zulu'), game('alpha.nes', 'Alpha')];

      expect(reseatUnfavoritedGame(games, 'Zulu.nes'), same(games));
    });

    test('an unknown romname is a no-op', () {
      final games = [game('alpha.nes', 'Alpha')];

      expect(reseatUnfavoritedGame(games, 'nope.nes'), same(games));
    });
  });
}
