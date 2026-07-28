/// Version parsing for the OTA update check.
///
/// Kept pure and dependency-free so the comparison can be tested directly.
///
/// Release tags and on-device version names are not plain `major.minor.patch`:
/// GitHub tags carry a `v` prefix and Flutter build metadata (`v0.9.7+121`),
/// and the Android flavors append a channel suffix (`0.9.7-dev`,
/// `0.9.7-feature`). Anything that cannot be read as a number is treated as
/// "cannot compare" rather than throwing.
library;

/// Parses [raw] into exactly three components, padding missing ones with 0.
///
/// Returns null when the string holds no usable numeric version. Build
/// metadata (`+121`) and pre-release/channel suffixes (`-dev`, `-rc.1`) are
/// discarded before parsing.
List<int>? parseVersion(String raw) {
  var value = raw.trim();
  if (value.isEmpty) return null;

  if (value.startsWith('v') || value.startsWith('V')) {
    value = value.substring(1);
  }
  value = value.split('+').first.split('-').first.trim();
  if (value.isEmpty) return null;

  final parts = value.split('.');
  final parsed = <int>[];
  for (var i = 0; i < 3; i++) {
    if (i >= parts.length) {
      parsed.add(0);
      continue;
    }
    final component = int.tryParse(parts[i].trim());
    if (component == null || component < 0) return null;
    parsed.add(component);
  }
  return parsed;
}

/// Whether [latest] is a strictly newer release than [current].
///
/// Returns false when either version is unparseable — an update check that
/// cannot read its own inputs must not offer an update.
///
/// Channel suffixes are stripped before comparing, so a dev or feature-test
/// build of the same version is treated as up to date. That is deliberate:
/// those channels are separate applicationIds and must never be offered the
/// production APK as an update.
bool isNewerVersion(String current, String latest) {
  final currentParts = parseVersion(current);
  final latestParts = parseVersion(latest);
  if (currentParts == null || latestParts == null) return false;

  for (var i = 0; i < 3; i++) {
    if (latestParts[i] != currentParts[i]) {
      return latestParts[i] > currentParts[i];
    }
  }
  return false;
}
