final RegExp _raDateZonePattern = RegExp(r'[+-]\d\d:\d\d$');

/// Parses RetroAchievements timestamps, treating zone-less values as UTC.
DateTime? parseRetroAchievementsDateUtc(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final normalized = raw.trim().replaceFirst(' ', 'T');
  final hasExplicitZone =
      normalized.endsWith('Z') || _raDateZonePattern.hasMatch(normalized);
  return DateTime.tryParse(
    hasExplicitZone ? normalized : '${normalized}Z',
  )?.toUtc();
}
