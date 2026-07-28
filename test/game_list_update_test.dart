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
}
