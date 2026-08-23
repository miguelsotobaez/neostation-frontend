/// Reading the disc list out of an `.m3u` multi-disc playlist.
///
/// RetroAchievements identifies a multi-disc game by its *first* disc, so a
/// playlist has to be resolved before anything can be hashed. On this library
/// that alone is worth 27 PlayStation matches, because the playlists point into
/// a hidden subfolder that nothing else looks in.
library;

/// The entries of an `.m3u`, in order, with comments and blank lines dropped.
///
/// Pure string work: resolving an entry against the playlist's own directory is
/// the caller's job, because that differs between a desktop path and an Android
/// SAF URI.
List<String> parseM3uEntries(String content) {
  final entries = <String>[];
  for (final rawLine in content.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    // `#EXTM3U` and friends are directives, not discs.
    if (line.startsWith('#')) continue;
    entries.add(line);
  }
  return entries;
}
