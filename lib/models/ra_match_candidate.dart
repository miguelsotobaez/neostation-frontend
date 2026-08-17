import 'ra_hash_policy.dart';

/// A ROM row selected for RetroAchievements hashing or re-matching.
///
/// Deliberately narrower than [GameModel]: the bulk passes only need enough to
/// hash the file and write the result back, and building full game models for
/// several thousand rows is wasted work.
class RaMatchCandidate {
  /// Path (or Android SAF content URI) of the ROM file.
  final String romPath;

  /// File name as stored in `user_roms`, used for progress messages.
  final String filename;

  /// Folder name of the owning system, used for archive extraction paths.
  final String systemFolderName;

  /// The system's RetroAchievements console id, used for the hash lookup.
  final String systemRaId;

  /// Hash already stored for this ROM, if any.
  final String? raHash;

  /// The owning system's hashing policy, carried on the row so the bulk pass
  /// does not have to look a system up per ROM.
  final RaHashPolicy policy;

  const RaMatchCandidate({
    required this.romPath,
    required this.filename,
    required this.systemFolderName,
    required this.systemRaId,
    required this.policy,
    this.raHash,
  });

  factory RaMatchCandidate.fromRow(Map<String, dynamic> row) {
    final hash = row['ra_hash']?.toString();
    return RaMatchCandidate(
      romPath: row['rom_path']?.toString() ?? '',
      filename: row['filename']?.toString() ?? '',
      systemFolderName: row['system_folder_name']?.toString() ?? '',
      systemRaId: row['system_ra_id']?.toString() ?? '',
      raHash: (hash != null && hash.isNotEmpty) ? hash : null,
      policy: RaHashPolicy.fromNames(
        row['ra_hash_algo']?.toString(),
        row['ra_hash_mode']?.toString(),
      ),
    );
  }

  /// Display label for progress reporting.
  String get label => filename.isNotEmpty ? filename : romPath;
}
