/// Parsing of `.cue` sheets, far enough to find a disc's data track and the
/// bytes behind it.
///
/// Pure string work with no file access, so it is unit-testable and the same
/// parser serves desktop paths and Android SAF URIs.
library;

/// One track declared by a cue sheet.
class CueTrack {
  /// The track number the sheet gives it, counting from 1.
  final int number;

  /// The declared mode, e.g. `MODE1/2352`, `MODE2/2352`, `AUDIO`.
  final String mode;

  /// The binary file this track's sectors live in, exactly as the sheet names
  /// it. Resolving it against a directory is the caller's job.
  final String file;

  /// Bytes per sector in that file.
  final int sectorSize;

  /// Where the track's user data starts inside each sector: raw 2352-byte
  /// sectors lead with a sync header, and MODE2 adds a subheader.
  final int dataOffset;

  /// Whether the track carries data rather than audio.
  final bool isData;

  /// Sectors into the file at which the track proper starts (its `INDEX 01`).
  final int indexOneInFile;

  /// Sectors of pregap the sheet declares with a `PREGAP` command.
  ///
  /// Those sectors exist in the disc's addressing but not in any file, so they
  /// shift every later track's sector numbers without contributing bytes.
  final int virtualPregap;

  const CueTrack({
    required this.number,
    required this.mode,
    required this.file,
    required this.sectorSize,
    required this.dataOffset,
    required this.isData,
    required this.indexOneInFile,
    required this.virtualPregap,
  });
}

/// A parsed cue sheet.
class CueSheet {
  /// The tracks, in the order the sheet declares them.
  final List<CueTrack> tracks;

  const CueSheet(this.tracks);

  /// Parses [content]. Lines it does not understand are ignored rather than
  /// rejected — cue sheets carry all sorts of optional commands, and none of
  /// the ones we skip change where a track's sectors are.
  factory CueSheet.parse(String content) {
    final tracks = <CueTrack>[];
    var currentFile = '';

    int? pendingNumber;
    String pendingMode = '';
    int pendingIndexOne = -1;
    int pendingPregap = 0;

    void flush() {
      if (pendingNumber == null) return;
      final size = _sectorSizeFor(pendingMode);
      tracks.add(
        CueTrack(
          number: pendingNumber!,
          mode: pendingMode,
          file: currentFile,
          sectorSize: size,
          dataOffset: _dataOffsetFor(pendingMode, size),
          isData: !pendingMode.startsWith('AUDIO'),
          // A track with no INDEX 01 starts where its file does; sheets in the
          // wild do omit it on single-track files.
          indexOneInFile: pendingIndexOne < 0 ? 0 : pendingIndexOne,
          virtualPregap: pendingPregap,
        ),
      );
      pendingNumber = null;
      pendingMode = '';
      pendingIndexOne = -1;
      pendingPregap = 0;
    }

    for (final rawLine in content.split('\n')) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final upper = line.toUpperCase();

      if (upper.startsWith('FILE ')) {
        flush();
        currentFile = _quotedArgument(line.substring(5).trim());
      } else if (upper.startsWith('TRACK ')) {
        flush();
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 3) {
          pendingNumber = int.tryParse(parts[1]);
          pendingMode = parts[2].toUpperCase();
        }
      } else if (upper.startsWith('INDEX ')) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 3 && int.tryParse(parts[1]) == 1) {
          pendingIndexOne = _msfToSectors(parts[2]);
        }
      } else if (upper.startsWith('PREGAP ')) {
        final parts = line.split(RegExp(r'\s+'));
        if (parts.length >= 2) pendingPregap = _msfToSectors(parts[1]);
      }
    }
    flush();

    return CueSheet(tracks);
  }

  /// The first track carrying data, or null when the sheet declares none.
  CueTrack? get firstDataTrack {
    for (final track in tracks) {
      if (track.isData) return track;
    }
    return null;
  }

  /// The files the sheet references, in order and without repeats.
  List<String> get files {
    final seen = <String>[];
    for (final track in tracks) {
      if (seen.isEmpty || seen.last != track.file) {
        if (!seen.contains(track.file)) seen.add(track.file);
      }
    }
    return seen;
  }
}

/// Strips the quotes a cue sheet puts around a filename, keeping any spaces
/// inside them and dropping the trailing `BINARY` / `WAVE` keyword.
String _quotedArgument(String value) {
  if (value.startsWith('"')) {
    final end = value.indexOf('"', 1);
    if (end > 0) return value.substring(1, end);
    return value.substring(1);
  }
  final space = value.indexOf(' ');
  return space < 0 ? value : value.substring(0, space);
}

/// `MM:SS:FF` to a sector count, at the CD's 75 frames per second.
int _msfToSectors(String value) {
  final parts = value.split(':');
  if (parts.length != 3) return 0;
  final minutes = int.tryParse(parts[0]) ?? 0;
  final seconds = int.tryParse(parts[1]) ?? 0;
  final frames = int.tryParse(parts[2]) ?? 0;
  return (minutes * 60 + seconds) * 75 + frames;
}

int _sectorSizeFor(String mode) {
  final slash = mode.indexOf('/');
  if (slash >= 0) {
    final declared = int.tryParse(mode.substring(slash + 1));
    if (declared != null && declared > 0) return declared;
  }
  // AUDIO and anything undeclared is raw.
  return 2352;
}

int _dataOffsetFor(String mode, int sectorSize) {
  if (sectorSize <= 2048) return 0;
  if (mode.startsWith('MODE2')) {
    // MODE2/2352 keeps the sync header and an 8-byte subheader; MODE2/2336
    // drops the sync header but keeps the subheader.
    return sectorSize >= 2352 ? 24 : 8;
  }
  // MODE1/2352: sync header and sector header.
  return 16;
}
