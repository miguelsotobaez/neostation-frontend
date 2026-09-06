import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/game_model.dart';
import 'package:neostation/models/my_systems.dart';

/// Which system a systems-screen card opens the settings dialog for.
///
/// Both entry points — the Y context menu and START — used to answer this
/// themselves, and drifted: the grid resolved a recent-activity card through
/// the game on it, while the carousel's START refused the same card as having
/// no system to configure. [SystemInfo.settingsFolderName] is the one answer
/// they now share.
void main() {
  GameModel game({String? systemFolderName}) => GameModel(
    romname: 'Game.z64',
    realname: 'Game',
    name: 'Game',
    year: '1996',
    developer: '',
    publisher: '',
    genre: '',
    players: '1',
    rating: 0,
    systemFolderName: systemFolderName,
  );

  test('a system card configures itself', () {
    expect(SystemInfo(folderName: 'snes').settingsFolderName, 'snes');
  });

  test('an aggregate card keeps its own virtual folder', () {
    expect(SystemInfo(folderName: 'all').settingsFolderName, 'all');
  });

  test('a recent-activity card configures the system its game belongs to', () {
    // The bug this getter exists for: the card's own folder name is the game's
    // rom name, which matches no detected system.
    final card = SystemInfo(
      folderName: 'Game.z64',
      isGame: true,
      gameModel: game(systemFolderName: 'n64'),
    );

    expect(card.settingsFolderName, 'n64');
  });

  test('a game card with no system falls back to its own folder', () {
    final card = SystemInfo(
      folderName: 'Game.z64',
      isGame: true,
      gameModel: game(),
    );

    // Nothing resolves this, and the callers report it as unavailable rather
    // than opening a dialog for the wrong hardware.
    expect(card.settingsFolderName, 'Game.z64');
  });
}
