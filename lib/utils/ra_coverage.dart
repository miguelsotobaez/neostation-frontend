/// Offline RetroAchievements coverage for a single ROM.
///
/// Every state here is derived from rows the database already holds: the match
/// (`user_roms.id_ra`), the computed hash (`user_roms.ra_hash`), the system's
/// RetroAchievements console (`app_systems.ra_id`) and the ROM's container.
/// Nothing in this file reaches the network, which is what lets the library
/// views badge thousands of tiles without an API call.
///
/// The states exist because "not matched" has four very different meanings and
/// conflating them makes the app look broken. Measured against a fully hashed
/// 9,133-ROM library, 96% of unmatched cartridge ROMs are games
/// RetroAchievements has simply never published a set for — a property of their
/// catalogue, not a gap in ours.
library;

/// What is known locally about a ROM's RetroAchievements coverage.
enum RaCoverage {
  /// RetroAchievements does not cover this system at all. Say nothing: there is
  /// no set to be missing.
  unsupportedSystem,

  /// A disc image. Disc hashing is not implemented yet, so an absent match here
  /// carries no information about whether the game has a set.
  pendingDiscSupport,

  /// Hashing has never been attempted for this ROM. "No achievements" would be
  /// a guess rather than a finding.
  notChecked,

  /// Hashed, and no set is registered for this dump. Overwhelmingly this means
  /// RetroAchievements never made a set for the game; a minority are games with
  /// a set whose registered dump differs from this one.
  noSet,

  /// Matched to a RetroAchievements game.
  matched,
}

/// Containers that hold a disc image rather than a cartridge dump.
///
/// Disc images are hashed from their primary executable, which needs a CHD /
/// ISO9660 reader the app does not have yet, so the plain whole-file MD5 they
/// currently get can never match. Kept here rather than in the hash service so
/// the UI can explain the gap without depending on the hashing layer.
const Set<String> kDiscImageExtensions = {
  'chd',
  'iso',
  'cue',
  'bin',
  'pbp',
  'm3u',
  'gdi',
  'ccd',
  'img',
  'mds',
  'nrg',
};

/// Whether [filename] names a disc image.
///
/// Takes a bare filename rather than a path on purpose: on Android `romPath` is
/// a SAF `content://` URI with `%2F`-encoded separators, and `user_roms`
/// already carries the plain filename alongside it.
bool isDiscImageFilename(String? filename) {
  if (filename == null) return false;
  final dot = filename.lastIndexOf('.');
  if (dot < 0 || dot == filename.length - 1) return false;
  return kDiscImageExtensions.contains(
    filename.substring(dot + 1).toLowerCase(),
  );
}

/// Whether [raId] names a real RetroAchievements console.
///
/// Systems the app knows but RetroAchievements does not carry a null, empty or
/// `'0'` id depending on how the definition was written.
bool isRaSupportedSystem(String? raId) {
  final id = raId?.trim();
  return id != null && id.isNotEmpty && id != '0';
}

/// Classifies a ROM from the fields the library queries already return.
RaCoverage raCoverageOf({
  required String? systemRaId,
  required String? filename,
  required String? raHash,
  required int? idRa,
}) {
  // A match outranks everything else: it was established somehow (hash, manual
  // pick, filename fallback) and the system's console id is irrelevant once a
  // game id is on the row.
  if (idRa != null && idRa > 0) return RaCoverage.matched;
  if (!isRaSupportedSystem(systemRaId)) return RaCoverage.unsupportedSystem;
  if (isDiscImageFilename(filename)) return RaCoverage.pendingDiscSupport;
  if (raHash == null || raHash.isEmpty) return RaCoverage.notChecked;
  return RaCoverage.noSet;
}

/// The coverage states the library can filter on, in the order the chip cycles.
///
/// [RaCoverage.unsupportedSystem] is deliberately absent: filtering to "systems
/// RetroAchievements does not cover" is a question about the systems list, not
/// about achievements, and the facet would swamp the chip on a library with
/// arcade or PC folders in it.
const List<RaCoverage> kFilterableRaCoverage = [
  RaCoverage.matched,
  RaCoverage.noSet,
  RaCoverage.notChecked,
  RaCoverage.pendingDiscSupport,
];
