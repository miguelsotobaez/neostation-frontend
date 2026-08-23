/// A ROM's dump identity as external databases index it.
///
/// These are hashes of the ROM image itself, not of the archive that happens to
/// contain it: ScreenScraper, No-Intro and Redump all key on the inner file.
/// Deliberately distinct from [GameModel.raHash], which is RetroAchievements'
/// own header-stripped, per-console transform and matches nothing else.
class RomFingerprint {
  /// Lowercase hex, 32 chars. Null when only the cheap crc path ran.
  final String? md5;

  /// Uppercase hex, 8 chars — the No-Intro convention ScreenScraper uses.
  /// ScreenScraper compares case-insensitively; the casing is for our logs.
  final String crc32;

  /// Size of the hashed image in bytes (ScreenScraper's `romtaille`).
  final int sizeBytes;

  const RomFingerprint({
    required this.crc32,
    required this.sizeBytes,
    this.md5,
  });

  RomFingerprint copyWith({String? md5, String? crc32, int? sizeBytes}) {
    return RomFingerprint(
      md5: md5 ?? this.md5,
      crc32: crc32 ?? this.crc32,
      sizeBytes: sizeBytes ?? this.sizeBytes,
    );
  }

  @override
  String toString() =>
      'RomFingerprint(crc32: $crc32, md5: ${md5 ?? "-"}, size: $sizeBytes)';
}
