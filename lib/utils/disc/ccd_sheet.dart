/// Parsing of CloneCD `.ccd` descriptors, far enough to lay a disc's table of
/// contents over the `.img` beside them.
///
/// Pure string work with no file access, so it is unit-testable and the same
/// parser serves desktop paths and Android SAF URIs.
library;

/// One track a `.ccd` declares.
class CcdTrack {
  /// The track number the descriptor gives it, counting from 1.
  final int number;

  /// The track's first sector, as the disc addresses it.
  final int startLba;

  /// Whether the track carries data rather than audio.
  final bool isData;

  /// Where the track's user data starts inside each raw sector.
  final int dataOffset;

  const CcdTrack({
    required this.number,
    required this.startLba,
    required this.isData,
    required this.dataOffset,
  });
}

/// A parsed `.ccd` descriptor.
class CcdSheet {
  /// The tracks, ordered by their start on the disc.
  final List<CcdTrack> tracks;

  const CcdSheet(this.tracks);

  /// Parses [content].
  ///
  /// A `.ccd` is an INI file of `[Entry n]` sections describing the disc's TOC
  /// and `[TRACK n]` sections describing what each track holds. Only the
  /// entries for real tracks are of interest: points `0xa0` and up are the
  /// lead-in and lead-out descriptors, which carry no sectors of their own.
  factory CcdSheet.parse(String content) {
    // Track number to the mode its `[TRACK n]` section declares.
    final modes = <int, int>{};
    // Track number to the entry the TOC gives it.
    final entries = <int, ({int startLba, bool isData})>{};

    var section = '';
    final values = <String, String>{};

    void flush() {
      if (section.startsWith('ENTRY ')) {
        final point = _parseInt(values['POINT']);
        // Points 1 to 99 are tracks; 0xa0 and up describe the session.
        if (point != null && point >= 1 && point <= 99) {
          final control = _parseInt(values['CONTROL']) ?? 0;
          final startLba = _parseInt(values['PLBA']) ?? 0;
          entries[point] = (
            startLba: startLba < 0 ? 0 : startLba,
            // Bit 2 of the control field marks a data track.
            isData: control & 0x04 != 0,
          );
        }
      } else if (section.startsWith('TRACK ')) {
        final number = _parseInt(section.substring(6).trim());
        final mode = _parseInt(values['MODE']);
        if (number != null && mode != null) modes[number] = mode;
      }
      values.clear();
    }

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('[') && line.endsWith(']')) {
        flush();
        section = line.substring(1, line.length - 1).trim().toUpperCase();
        continue;
      }

      final equals = line.indexOf('=');
      if (equals > 0) {
        values[line.substring(0, equals).trim().toUpperCase()] = line
            .substring(equals + 1)
            .trim();
      }
    }
    flush();

    final tracks = <CcdTrack>[];
    for (final entry in entries.entries) {
      final mode = modes[entry.key];
      tracks.add(
        CcdTrack(
          number: entry.key,
          startLba: entry.value.startLba,
          // A `MODE=0` section is an audio track however the TOC flagged it.
          isData: entry.value.isData && mode != 0,
          dataOffset: _dataOffsetFor(mode),
        ),
      );
    }
    tracks.sort((a, b) => a.startLba.compareTo(b.startLba));
    return CcdSheet(tracks);
  }
}

/// Every sector in a CloneCD `.img` is raw, so what varies is only how much of
/// one the header takes.
const int ccdSectorSize = 2352;

/// Where a mode's user data starts inside a raw sector.
///
/// MODE1 leads with a 12-byte sync pattern and a 4-byte address; MODE2 adds an
/// 8-byte subheader. An undeclared mode is read as MODE2, which is what a
/// PlayStation or PC Engine disc — the discs that come as `.ccd` at all — holds.
int _dataOffsetFor(int? mode) => switch (mode) {
  0 => 0,
  1 => 16,
  _ => 24,
};

/// Reads a decimal or `0x`-prefixed hexadecimal field.
int? _parseInt(String? value) {
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
    return int.tryParse(trimmed.substring(2), radix: 16);
  }
  return int.tryParse(trimmed);
}
