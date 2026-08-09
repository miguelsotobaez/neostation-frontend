import '../models/game_model.dart';

/// Returns a new games list with [updatedGame] replacing the matching ROM.
///
/// A new list identity is intentional: game-view widgets use it to distinguish
/// changed card content from ordinary selection changes. If no game matches,
/// the original list is returned unchanged.
List<GameModel> replaceGameInList(
  List<GameModel> games,
  GameModel updatedGame,
) {
  final index = games.indexWhere((game) => game.romname == updatedGame.romname);
  if (index == -1) return games;

  return List<GameModel>.of(games)..[index] = updatedGame;
}
