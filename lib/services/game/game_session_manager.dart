import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:neostation/services/logger_service.dart';
import '../../models/game_model.dart';
import '../../models/system_model.dart';
import '../../repositories/game_repository.dart';
import '../../repositories/system_repository.dart';
import '../game_session_persistence.dart';

/// Owns the game-session lifecycle and its mutable tracking state.
///
/// Single owner of the launch/session flags, the current-game metadata, the
/// return/exit callbacks, and the playtime timer. Registers a session on
/// launch, persists playtime incrementally, and finalizes it on teardown, plus
/// recovery of a session interrupted by an OS kill. Extracted verbatim from
/// [GameService], which now delegates its session API here and calls
/// [registerGameLaunch]/[endGameSession] from its launch methods.
class GameSessionManager {
  GameSessionManager._();

  static final _log = LoggerService.instance;

  /// Whether a game process is currently active.
  static bool _isGameLaunched = false;
  static bool get isGameLaunched => _isGameLaunched;

  /// True from the moment a launch is initiated (Now Playing pushed) until the
  /// launch resolves — i.e. [registerGameLaunch] flips [_isGameLaunched], or
  /// the launch fails. Covers the ~2s dialog+handoff window during which
  /// [_isGameLaunched] is still false, so a transient resume in that window
  /// can't clear the Now Playing state we just pushed.
  static bool _launchPending = false;

  /// Whether a game is running OR a launch is in progress. Callers reacting to
  /// an app resume should use this (not [isGameLaunched]) before clearing
  /// secondary-display in-game state, to avoid a launch-window race.
  static bool get isGameLaunchInProgress => _isGameLaunched || _launchPending;

  /// Opens the launch-pending window. Call when a launch is initiated, before
  /// the emulator handoff. Cleared by [registerGameLaunch] on success or
  /// [clearLaunchPending] on failure.
  static void beginLaunchPending() => _launchPending = true;

  /// Closes the launch-pending window (e.g. on launch failure).
  static void clearLaunchPending() => _launchPending = false;

  /// Timestamp when the current game session was initiated.
  static DateTime? _gameLaunchTime;
  static DateTime? get gameLaunchTime => _gameLaunchTime;

  /// Filename of the standalone emulator executable currently running.
  static String? _launchedEmulatorExe;
  static String? get launchedEmulatorExe => _launchedEmulatorExe;

  /// Metadata for the system associated with the current game.
  static SystemModel? _currentGameSystem;

  /// Metadata for the currently active game.
  static GameModel? _currentGame;

  /// Callback triggered when a game session terminates on Android.
  static Function(int)? _onGameReturnedCallback;
  static Function(int)? get onGameReturnedCallback => _onGameReturnedCallback;

  /// Callback triggered when the game process exits on desktop platforms.
  static Function()? _onProcessExitCallback;

  /// Periodic timer for persisting playtime statistics to the database.
  static Timer? _playtimeTimer;

  /// Timestamp of the last successful playtime persistence operation.
  static DateTime? _lastPlaytimeSave;

  static void setOnGameReturnedCallback(Function(int) callback) {
    _onGameReturnedCallback = callback;
  }

  static void clearOnGameReturnedCallback() {
    _onGameReturnedCallback = null;
  }

  static void setOnProcessExitCallback(Function() callback) {
    _onProcessExitCallback = callback;
  }

  static void clearOnProcessExitCallback() {
    _onProcessExitCallback = null;
  }

  /// Recovers playtime from a previously interrupted game session.
  ///
  /// Handles cases where the application was terminated by the OS (Android)
  /// while a game was running.
  static Future<void> checkPendingGameSession() async {
    try {
      final session = await GameSessionPersistence.getActiveGameSession();

      if (session == null) {
        return;
      }

      final systemFolderName = session['systemFolderName'].toString();
      final filename = session['filename'].toString();
      final startTimestamp =
          int.tryParse(session['startTimestamp']?.toString() ?? '0') ?? 0;

      final currentTimestamp = DateTime.now().millisecondsSinceEpoch;
      final elapsedSeconds = ((currentTimestamp - startTimestamp) / 1000)
          .round();

      // Only process sessions that lasted at least 5 seconds to filter out launch failures
      if (elapsedSeconds >= 5) {
        final system = await SystemRepository.getSystemByFolderName(
          systemFolderName,
        );
        if (system == null) return;
        final game = await GameRepository.getSingleGame(system.id!, filename);

        if (game != null && game.romPath.isNotEmpty) {
          await GameRepository.updatePlayTime(game.romPath, elapsedSeconds);
        }
      }

      await GameSessionPersistence.clearGameSession();
    } catch (e) {
      _log.e('Error checking pending game session: $e');
    }
  }

  /// Registers the initiation of a game session and initializes tracking state.
  static void registerGameLaunch(
    SystemModel system,
    GameModel game, [
    String? emulatorExeName,
  ]) {
    _isGameLaunched = true;
    _launchPending = false;
    _gameLaunchTime = DateTime.now();
    _lastPlaytimeSave = _gameLaunchTime;
    _launchedEmulatorExe = emulatorExeName;
    _currentGameSystem = system;
    _currentGame = game;

    if (Platform.isAndroid) {
      GameSessionPersistence.saveGameSession(
        systemFolderName: system.folderName,
        filename: game.romname,
        startTimestamp: _gameLaunchTime!.millisecondsSinceEpoch,
      );
    }

    _startPlaytimeTimer();
  }

  /// Starts the periodic timer for incremental playtime persistence.
  static void _startPlaytimeTimer() {
    _playtimeTimer?.cancel();

    _playtimeTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
      if (_isGameLaunched &&
          _gameLaunchTime != null &&
          _lastPlaytimeSave != null &&
          _currentGameSystem != null &&
          _currentGame != null) {
        final now = DateTime.now();
        final elapsedSinceLastSave = now
            .difference(_lastPlaytimeSave!)
            .inSeconds;

        if (elapsedSinceLastSave > 0) {
          _savePlayTime(
            _currentGameSystem!,
            _currentGame!,
            elapsedSinceLastSave,
          );
          _lastPlaytimeSave = now;
        }
      }
    });
  }

  static void _stopPlaytimeTimer() {
    _playtimeTimer?.cancel();
    _playtimeTimer = null;
  }

  /// Gracefully terminates the active game session and finalizes playtime tracking.
  static Future<void> endGameSession() async {
    if (!_isGameLaunched) return;

    if (_gameLaunchTime != null &&
        _lastPlaytimeSave != null &&
        _currentGameSystem != null &&
        _currentGame != null) {
      final now = DateTime.now();
      final elapsedSinceLastSave = now.difference(_lastPlaytimeSave!).inSeconds;
      if (elapsedSinceLastSave > 0) {
        await _savePlayTime(
          _currentGameSystem!,
          _currentGame!,
          elapsedSinceLastSave,
        );
      }
    }

    _stopPlaytimeTimer();

    if (Platform.isAndroid) {
      const platform = MethodChannel('com.neogamelab.neostation/game');
      await platform.invokeMethod('setGamepadBlock', {'block': false});
      GameSessionPersistence.clearGameSession();
    } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (_onProcessExitCallback != null) {
        _onProcessExitCallback!();
      }
    }

    _isGameLaunched = false;
    _gameLaunchTime = null;
    _lastPlaytimeSave = null;
    _launchedEmulatorExe = null;
    _currentGameSystem = null;
    _currentGame = null;
  }

  static Future<void> _savePlayTime(
    SystemModel system,
    GameModel game,
    int elapsedSeconds,
  ) async {
    try {
      await GameRepository.updatePlayTime(game.romPath!, elapsedSeconds);
    } catch (e) {
      _log.e('Error saving game time: $e');
    }
  }
}
