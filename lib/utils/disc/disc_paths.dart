/// Resolving the file references inside `.cue` sheets and `.m3u` playlists.
///
/// Both name their companions relative to themselves, and on Android the
/// container's own path is a SAF `content://` URI whose separators are
/// `%2F`-encoded — so a plain path join produces something that looks right and
/// resolves to nothing.
library;

/// Resolves [reference] against the directory holding [containerPath].
///
/// [reference] may name a subdirectory (`.hidden/Game (Disc 1).chd`, which is
/// how multi-disc playlists here are written) with either separator. An
/// absolute reference is returned unchanged.
String resolveDiscSibling(String containerPath, String reference) {
  final trimmed = reference.trim();
  if (trimmed.isEmpty) return trimmed;

  if (trimmed.startsWith('content://') ||
      trimmed.startsWith('/') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(trimmed)) {
    return trimmed;
  }

  final segments = trimmed
      .split(RegExp(r'[\\/]'))
      .where((segment) => segment.isNotEmpty && segment != '.')
      .toList();
  if (segments.isEmpty) return trimmed;

  // A SAF document URI encodes the whole path into one component, so the
  // separator is literal `%2F` text rather than a slash.
  for (final encoded in const ['%2F', '%2f']) {
    final index = containerPath.lastIndexOf(encoded);
    if (index > 0) {
      final directory = containerPath.substring(0, index + encoded.length);
      return directory + segments.map(Uri.encodeComponent).join(encoded);
    }
  }

  for (final separator in const ['/', r'\']) {
    final index = containerPath.lastIndexOf(separator);
    if (index >= 0) {
      final directory = containerPath.substring(0, index + 1);
      return directory + segments.join(separator);
    }
  }

  return segments.join('/');
}
