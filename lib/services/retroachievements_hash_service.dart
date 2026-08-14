import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:neostation/services/logger_service.dart';
import '../models/game_model.dart';
import '../models/ra_match_candidate.dart';
import '../repositories/retro_achievements_repository.dart';
import '../repositories/system_repository.dart';
import '../utils/optimized_md5_utils.dart';
import 'archive_service.dart';

/// Service responsible for generating system-specific hashes required by
/// RetroAchievements (RA) for game identification.
///
/// RA uses different hashing algorithms depending on the platform (e.g., NES
/// hashes excluding headers, SNES hashes with specific offsets). This service
/// coordinates these algorithms, handles archive extraction, and offloads
/// processing to background isolates.
class RetroAchievementsHashService {
  /// Maximum file size permitted for hash generation (512 MB).
  static const int maxFileSizeBytes = 512 * 1024 * 1024;

  static final _log = LoggerService.instance;

  /// Generates the appropriate RA hash for a specific game if not already present.
  ///
  /// Checks local cache (SQLite) before attempting generation. Handles temporary
  /// extraction for compressed files and offloads the MD5 calculation to an
  /// isolate via [compute].
  static Future<String?> generateHashForGame(GameModel game) async {
    try {
      if (game.raHash != null && game.raHash!.isNotEmpty) {
        return game.raHash;
      }

      if (game.romPath == null) return null;

      if (!await OptimizedMd5Utils.fileExists(game.romPath!)) {
        return null;
      }

      final existingHash = await RetroAchievementsRepository.getRomRaHash(
        game.romPath!,
      );
      if (existingHash != null && existingHash.isNotEmpty) {
        return existingHash;
      }

      final fileSize = await OptimizedMd5Utils.getFileSize(game.romPath!);
      if (fileSize > maxFileSizeBytes) {
        return null;
      }

      String romPathToProcess = game.romPath!;
      final bool isArchive =
          (romPathToProcess.toLowerCase().endsWith('.zip') ||
              romPathToProcess.toLowerCase().endsWith('.7z')) &&
          !isArcadeSystem(game.systemFolderName);

      if (isArchive) {
        final extractedPath = await ArchiveService.extractRom(
          romPathToProcess,
          game.systemFolderName ?? 'unknown',
        );
        if (extractedPath != null) {
          romPathToProcess = extractedPath;
        } else {
          _log.w(
            'Failed to extract compressed file, aborting hash: ${game.name}',
          );
          return null;
        }
      }

      await Future.delayed(const Duration(milliseconds: 500));

      final isolateToken = RootIsolateToken.instance!;
      final hash = await compute(_generateHashForSystemIsolate, {
        'romPath': romPathToProcess,
        'systemFolderName': game.systemFolderName,
        'gameName': game.name,
        'token': isolateToken,
      });

      if (isArchive) {
        await ArchiveService.cleanupTempFolder(
          game.systemFolderName ?? 'unknown',
          game.romPath!,
        );
      }

      if (hash != null && hash.isNotEmpty) {
        await RetroAchievementsRepository.updateRomRaHash(game.romPath!, hash);

        if (game.systemFolderName != null) {
          final system = await SystemRepository.getSystemByFolderName(
            game.systemFolderName!,
          );
          if (system != null && system.raId != null) {
            await _lookupAndSaveGameId(
              hash,
              system.raId!,
              game.romPath!,
              game.name,
            );
          }
        }
      }

      return hash;
    } catch (e) {
      _log.e('Error generating hash for ${game.name}: $e');
      return null;
    }
  }

  /// Runs a library-wide RetroAchievements matching pass.
  ///
  /// Hashing is otherwise lazy — a ROM is only hashed when the user opens it —
  /// so a library that has never been browsed game by game is almost entirely
  /// unmatched. This walks the whole library instead.
  ///
  /// [RaRematchMode.lookupOnly] retries the local game-id lookup for ROMs that
  /// already carry a hash; it touches no files and is cheap enough to re-run
  /// whenever the bundled RA database changes.
  /// [RaRematchMode.hashMissing] hashes ROMs that have never been hashed.
  ///
  /// Rows the user matched by hand are never overwritten — the write guard
  /// lives in [RetroAchievementsRepository].
  static Future<RaRematchResult> rematchLibrary({
    RaRematchMode mode = RaRematchMode.hashMissing,
    bool includeDiscSystems = false,
    void Function(int processed, int total, String label)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final candidates = mode == RaRematchMode.lookupOnly
        ? await RetroAchievementsRepository.getRomsNeedingRaGameId()
        : await RetroAchievementsRepository.getRomsNeedingRaHash(
            includeDiscSystems: includeDiscSystems,
          );

    final total = candidates.length;
    int processed = 0;
    int hashed = 0;
    int matched = 0;
    int skipped = 0;

    _log.i('RA re-match (${mode.name}): $total candidate ROMs');

    for (final candidate in candidates) {
      if (isCancelled?.call() ?? false) {
        _log.i('RA re-match cancelled after $processed of $total');
        return RaRematchResult(
          total: total,
          processed: processed,
          hashed: hashed,
          matched: matched,
          skipped: skipped,
          cancelled: true,
        );
      }

      onProgress?.call(processed, total, candidate.label);

      try {
        if (mode == RaRematchMode.lookupOnly) {
          if (await _lookupAndSaveGameId(
            candidate.raHash!,
            candidate.systemRaId,
            candidate.romPath,
            candidate.label,
          )) {
            matched++;
          }
        } else {
          final hash = await _hashCandidate(candidate);
          if (hash == null) {
            skipped++;
          } else {
            hashed++;
            await RetroAchievementsRepository.updateRomRaHash(
              candidate.romPath,
              hash,
            );
            if (await _lookupAndSaveGameId(
              hash,
              candidate.systemRaId,
              candidate.romPath,
              candidate.label,
            )) {
              matched++;
            }
          }
        }
      } catch (e) {
        _log.e('RA re-match failed for ${candidate.label}: $e');
        skipped++;
      }

      processed++;
    }

    onProgress?.call(processed, total, '');
    _log.i(
      'RA re-match finished: $processed processed, $hashed hashed, '
      '$matched matched, $skipped skipped',
    );

    return RaRematchResult(
      total: total,
      processed: processed,
      hashed: hashed,
      matched: matched,
      skipped: skipped,
      cancelled: false,
    );
  }

  /// Hashes a single bulk-pass candidate, or returns null when the ROM cannot
  /// usefully be hashed (missing, oversized, a disc image, or extraction
  /// failed).
  static Future<String?> _hashCandidate(RaMatchCandidate candidate) async {
    if (isDiscContainer(candidate.romPath)) {
      // A disc image needs RA's own disc hashing, not a hash of the container.
      return null;
    }

    if (!await OptimizedMd5Utils.fileExists(candidate.romPath)) {
      _log.w('File not found, skipping: ${candidate.romPath}');
      return null;
    }

    if (await OptimizedMd5Utils.getFileSize(candidate.romPath) >
        maxFileSizeBytes) {
      return null;
    }

    String romPathToProcess = candidate.romPath;
    final lowerPath = romPathToProcess.toLowerCase();
    final bool isArchive =
        (lowerPath.endsWith('.zip') || lowerPath.endsWith('.7z')) &&
        !isArcadeSystem(candidate.systemFolderName);

    if (isArchive) {
      final extractedPath = await ArchiveService.extractRom(
        romPathToProcess,
        candidate.systemFolderName,
      );
      if (extractedPath == null) {
        _log.w('Failed to extract, skipping: ${candidate.label}');
        return null;
      }
      romPathToProcess = extractedPath;
    }

    try {
      final hash = await compute(_generateHashForSystemIsolate, {
        'romPath': romPathToProcess,
        'systemFolderName': candidate.systemFolderName,
        'gameName': candidate.label,
        'token': RootIsolateToken.instance!,
      });
      return (hash != null && hash.isNotEmpty) ? hash : null;
    } finally {
      if (isArchive) {
        await ArchiveService.cleanupTempFolder(
          candidate.systemFolderName,
          candidate.romPath,
        );
      }
    }
  }

  /// Whether [romPath] points at a disc image whose container hash is
  /// meaningless to RetroAchievements.
  ///
  /// Systems flagged as disc-based are already filtered out in SQL; this
  /// catches a stray disc image sitting in a cartridge system's folder.
  /// Extensions shared with cartridge dumps (`.bin`, `.iso` on some systems)
  /// are deliberately left to the per-system filter.
  static bool isDiscContainer(String romPath) {
    final lower = romPath.toLowerCase();
    for (final ext in const [
      '.chd',
      '.cue',
      '.gdi',
      '.cdi',
      '.pbp',
      '.m3u',
      '.ccd',
      '.mds',
      '.mdf',
      '.nrg',
      '.cso',
      '.rvz',
      '.wbfs',
      '.wia',
      '.gcm',
    ]) {
      if (lower.endsWith(ext)) return true;
    }
    return false;
  }

  /// Determines if a specific system requires a non-standard hashing algorithm
  /// recognized by RetroAchievements.
  static bool hasSpecificHashGenerator(String? systemFolderName) {
    if (systemFolderName == null) return false;
    final system = systemFolderName.toLowerCase();

    return system == 'nes' ||
        system == 'fc' ||
        system == 'ds' ||
        system == 'snes' ||
        system == 'sfc' ||
        system == 'satellaview' ||
        system == 'arc' ||
        system == 'fbneo' ||
        system == 'neogeo' ||
        system == 'naomi' ||
        system == 'naomi2' ||
        system == 'naomigd' ||
        system == 'aw' ||
        system == 'cps1' ||
        system == 'cps2' ||
        system == 'cps3' ||
        system == 'mame' ||
        system == 'gb' ||
        system == 'gbc' ||
        system == 'gba' ||
        system == 'vb' ||
        system == 'ngp' ||
        system == 'ngpc' ||
        system == '32x' ||
        system == 'sms' ||
        system == 'mark3' ||
        system == 'wasm4' ||
        system == 'md' ||
        system == 'genesis' ||
        system == 'jag' ||
        system == 'ws' ||
        system == 'wsc' ||
        system == 'chf' ||
        system == 'vect' ||
        system == 'mo2' ||
        system == 'intv' ||
        system == 'cv' ||
        system == '2600' ||
        system == '7800' ||
        system == 'lynx' ||
        system == 'ard' ||
        system == 'n64' ||
        system == 'sg1k' ||
        system == 'duck' ||
        system == 'wsv' ||
        system == 'gg' ||
        system == 'mini';
  }

  /// Identifies if a system belongs to the Arcade category, where ROM archives
  /// (ZIPs) should not be extracted for hashing.
  static bool isArcadeSystem(String? systemFolderName) {
    if (systemFolderName == null) return false;
    final system = systemFolderName.toLowerCase();
    return system == 'arc' ||
        system == 'fbneo' ||
        system == 'neogeo' ||
        system == 'naomi' ||
        system == 'naomi2' ||
        system == 'naomigd' ||
        system == 'aw' ||
        system == 'cps1' ||
        system == 'cps2' ||
        system == 'cps3' ||
        system == 'mame';
  }

  /// Top-level function executed in a background isolate to compute system-specific hashes.
  static Future<String?> _generateHashForSystemIsolate(
    Map<String, dynamic> params,
  ) async {
    final token = params['token'] as RootIsolateToken?;
    if (token != null) {
      BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    }

    final romPath = params['romPath'].toString();
    final systemFolderName = params['systemFolderName']?.toString();
    final systemFolder = systemFolderName?.toLowerCase() ?? '';

    try {
      String? hash;

      if (systemFolder == 'nes' ||
          systemFolder == 'fc' ||
          systemFolder == 'famicom' ||
          systemFolder == 'fds') {
        hash = await OptimizedMd5Utils.calculateNesMd5(romPath);
      } else if (systemFolder == 'ds') {
        hash = await OptimizedMd5Utils.calculateDsMd5(romPath);
      } else if (systemFolder == 'arc' ||
          systemFolder == 'fbneo' ||
          systemFolder == 'neogeo' ||
          systemFolder == 'naomi' ||
          systemFolder == 'naomi2' ||
          systemFolder == 'naomigd' ||
          systemFolder == 'aw' ||
          systemFolder == 'cps1' ||
          systemFolder == 'cps2' ||
          systemFolder == 'cps3' ||
          systemFolder == 'mame') {
        hash = OptimizedMd5Utils.calculateArcadeMd5(romPath);
      } else if (systemFolder == 'snes' ||
          systemFolder == 'sfc' ||
          systemFolder == 'satellaview') {
        hash = await OptimizedMd5Utils.calculateSnesMd5(romPath);
      } else if (systemFolder == '7800') {
        hash = await OptimizedMd5Utils.calculateAtari7800Md5(romPath);
      } else if (systemFolder == 'lynx') {
        hash = await OptimizedMd5Utils.calculateLynxMd5(romPath);
      } else if (systemFolder == 'ard') {
        hash = await OptimizedMd5Utils.calculateArduboyMd5(romPath);
      } else if (systemFolder == 'n64') {
        hash = await OptimizedMd5Utils.calculateN64Md5(romPath);
      } else {
        hash = await OptimizedMd5Utils.calculateFileMd5(romPath);
      }

      return hash;
    } catch (e) {
      _log.e('Error generating hash for system $systemFolder: $e');
      return null;
    }
  }

  /// Searches for the RetroAchievements Game ID in the local database using the
  /// generated hash and updates the game metadata.
  ///
  /// Returns whether a game id was found and stored.
  static Future<bool> _lookupAndSaveGameId(
    String raHash,
    String raConsoleId,
    String romPath,
    String label,
  ) async {
    try {
      final gameId = await RetroAchievementsRepository.getGameIdByHash(
        raHash,
        raConsoleId,
      );

      if (gameId == null) {
        _log.w('No game ID found in internal DB for RA hash: $label');
        return false;
      }

      await RetroAchievementsRepository.updateRomRaGameId(
        romPath,
        gameId,
        matchSource: RetroAchievementsRepository.raMatchHash,
      );
      return true;
    } catch (e) {
      _log.e('Error looking up game ID by hash: $e');
      return false;
    }
  }
}

/// Which pass [RetroAchievementsHashService.rematchLibrary] should run.
enum RaRematchMode {
  /// Retry the local game-id lookup for ROMs that already have a hash.
  /// Touches no files.
  lookupOnly,

  /// Hash ROMs that have never been hashed, then look them up.
  hashMissing,
}

/// Outcome of a [RetroAchievementsHashService.rematchLibrary] pass.
class RaRematchResult {
  /// Candidate ROMs the pass started with.
  final int total;

  /// Candidates actually visited (less than [total] when cancelled).
  final int processed;

  /// ROMs that produced a new hash.
  final int hashed;

  /// ROMs that gained a RetroAchievements game id.
  final int matched;

  /// ROMs that could not be hashed — missing, oversized, a disc image, or a
  /// failed archive extraction.
  final int skipped;

  /// Whether the user stopped the pass before it finished.
  final bool cancelled;

  const RaRematchResult({
    required this.total,
    required this.processed,
    required this.hashed,
    required this.matched,
    required this.skipped,
    required this.cancelled,
  });

  bool get hasResults => hashed > 0 || matched > 0;
}
