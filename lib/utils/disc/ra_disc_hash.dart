import 'dart:convert';

import '../../models/ra_hash_policy.dart';
import '../../services/logger_service.dart';
import '../optimized_md5_utils.dart';
import 'binary_disc_image.dart';
import 'chd_disc_image.dart';
import 'disc_image.dart';
import 'disc_paths.dart';
import 'm3u_playlist.dart';
import 'ra_disc_hasher.dart';

/// Produces the hash RetroAchievements would recognise for a disc image.
class RaDiscHash {
  static final _log = LoggerService.instance;

  /// Containers this can read. Anything else is left to the caller to park as
  /// unhashable rather than hashed wrongly.
  static const Set<String> supportedExtensions = {
    '.chd',
    '.cue',
    '.iso',
    '.bin',
    '.img',
    '.m3u',
    '.pbp',
  };

  /// Whether [romPath] is a container this can open.
  static bool canHash(String romPath) {
    final lower = romPath.toLowerCase();
    return supportedExtensions.any(lower.endsWith);
  }

  /// Hashes the disc at [romPath] the way [algo]'s console expects, or returns
  /// null when the image cannot be read or holds no recognisable game.
  static Future<String?> compute(RaHashAlgo algo, String romPath) async {
    if (!algo.isDisc) return null;

    final resolved = await _resolvePlaylist(romPath);
    if (resolved == null) return null;

    // A PSP `.pbp` is an archive of the metadata and the executable both, so
    // RetroAchievements hashes the whole file rather than unpacking it.
    if (resolved.toLowerCase().endsWith('.pbp')) {
      if (algo != RaHashAlgo.psp) return null;
      return OptimizedMd5Utils.calculateFileMd5(resolved);
    }

    final image = await _openImage(resolved);
    if (image == null) {
      _log.w('RA disc: could not open $resolved');
      return null;
    }

    try {
      final trackIndex = _trackIndexFor(algo, image);
      if (trackIndex < 0) {
        _log.w('RA disc: no usable track in $resolved');
        return null;
      }
      final track = DiscTrack(image, trackIndex);

      return switch (algo) {
        RaHashAlgo.psx => await RaDiscHasher.hashPlaystation(track),
        RaHashAlgo.ps2 => await RaDiscHasher.hashPlaystation2(track),
        RaHashAlgo.psp => await RaDiscHasher.hashPsp(track),
        RaHashAlgo.segacd ||
        RaHashAlgo.saturn => await RaDiscHasher.hashSegaDisc(track),
        RaHashAlgo.pcecd => await RaDiscHasher.hashPcEngineCd(track),
        _ => null,
      };
    } finally {
      await image.close();
    }
  }

  /// Opens whichever container [path] names.
  static Future<DiscImage?> _openImage(String path) async {
    final lower = path.toLowerCase();
    if (lower.endsWith('.chd')) return ChdDiscImage.open(path);
    if (lower.endsWith('.cue')) return BinaryDiscImage.openCue(path);
    return BinaryDiscImage.openImage(path);
  }

  /// Which track a console's data lives on.
  ///
  /// PlayStation and Sega discs put it first; a PC Engine CD leads with an
  /// audio track often enough that the first *data* track is the only reliable
  /// answer there.
  static int _trackIndexFor(RaHashAlgo algo, DiscImage image) {
    if (algo == RaHashAlgo.pcecd) return image.firstDataTrackIndex;
    for (var i = 0; i < image.tracks.length; i++) {
      if (image.tracks[i].number == 1) return i;
    }
    return image.tracks.isEmpty ? -1 : 0;
  }

  /// Follows an `.m3u` to its first disc, which is the one RetroAchievements
  /// registers a multi-disc game under. Any other path is returned unchanged.
  static Future<String?> _resolvePlaylist(String romPath) async {
    if (!romPath.toLowerCase().endsWith('.m3u')) return romPath;

    if (!await OptimizedMd5Utils.fileExists(romPath)) return null;
    final bytes = await OptimizedMd5Utils.readAllBytes(romPath);
    if (bytes.isEmpty) return null;

    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }

    final entries = parseM3uEntries(text);
    if (entries.isEmpty) {
      _log.w('RA disc: empty playlist $romPath');
      return null;
    }

    final first = resolveDiscSibling(romPath, entries.first);
    if (!await OptimizedMd5Utils.fileExists(first)) {
      _log.w('RA disc: playlist points at a missing disc: ${entries.first}');
      return null;
    }
    return first;
  }
}
