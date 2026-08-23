import 'dart:convert';
import 'dart:typed_data';

import '../optimized_md5_utils.dart';
import 'cue_sheet.dart';
import 'disc_image.dart';
import 'disc_paths.dart';

/// A disc image made of plain sector data in one or more files: `.iso`, a bare
/// `.bin`, or a `.cue` sheet naming several of them.
///
/// No native code is involved — the only thing that varies is where a sector's
/// 2048 user bytes sit inside whatever the file stores per sector.
class BinaryDiscImage extends DiscImage {
  /// How many raw sectors one read pulls in.
  ///
  /// Sector reads used to go out one at a time, and on Android every one of
  /// them is a platform-channel round trip for 2 KB. That is invisible for the
  /// systems that hash a boot executable or a 512-byte header, and brutal for
  /// PSP, which hashes the whole of `EBOOT.BIN`: 5.6 MB is ~2,900 round trips,
  /// measured at ~5.3 s per game on an AYN Thor. CHD images never had the
  /// problem — libchdr reads and caches whole hunks behind one open handle.
  ///
  /// Reads here are sequential by construction (walk the ISO9660 tree, then
  /// stream one file), so a window is fetched once and sliced.
  static const int _windowSectors = 256;

  final List<_BinaryTrack> _tracks;

  /// The window: raw bytes as stored, so slicing still has to apply the
  /// track's own sector size and data offset.
  Uint8List? _window;
  int _windowTrack = -1;
  int _windowFirstSector = -1;

  BinaryDiscImage._(this._tracks);

  @override
  List<DiscTrackInfo> get tracks => _tracks.map((t) => t.info).toList();

  /// Opens a single-track image: an `.iso`, or a `.bin` with no sheet beside it.
  ///
  /// The sector layout is probed rather than assumed from the extension: a PS1
  /// `.bin` is 2352-byte MODE2 sectors while a PS2 `.iso` is a flat 2048, and
  /// both extensions get used for both.
  static Future<BinaryDiscImage?> openImage(String path) async {
    if (!await OptimizedMd5Utils.fileExists(path)) return null;
    final size = await OptimizedMd5Utils.getFileSize(path);
    if (size <= 0) return null;

    final layout = await _probeLayout(path, size);
    if (layout == null) return null;

    return BinaryDiscImage._([
      _BinaryTrack(
        info: DiscTrackInfo(
          number: 1,
          isData: true,
          startLba: 0,
          sectors: size ~/ layout.sectorSize,
        ),
        path: path,
        sectorSize: layout.sectorSize,
        dataOffset: layout.dataOffset,
        fileStartSector: 0,
      ),
    ]);
  }

  /// Opens a `.cue` sheet and the binaries it names.
  static Future<BinaryDiscImage?> openCue(String cuePath) async {
    if (!await OptimizedMd5Utils.fileExists(cuePath)) return null;
    final bytes = await OptimizedMd5Utils.readAllBytes(cuePath);
    if (bytes.isEmpty) return null;

    // Cue sheets are usually ASCII but sometimes carry accented filenames in a
    // legacy encoding; latin1 decodes any byte rather than throwing, and the
    // fields we read are ASCII either way.
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      text = latin1.decode(bytes);
    }

    final sheet = CueSheet.parse(text);
    if (sheet.tracks.isEmpty) return null;

    final tracks = <_BinaryTrack>[];
    // Where the current file's first sector sits in the disc's addressing.
    var fileBaseLba = 0;
    var virtualOffset = 0;
    String? currentFile;
    String? currentPath;
    var currentFileSectors = 0;

    for (final track in sheet.tracks) {
      if (track.file != currentFile) {
        if (currentFile != null) fileBaseLba += currentFileSectors;
        currentFile = track.file;
        currentPath = await _resolveSibling(cuePath, track.file);
        final size = currentPath == null
            ? 0
            : await OptimizedMd5Utils.getFileSize(currentPath);
        currentFileSectors = size ~/ track.sectorSize;
      }
      if (currentPath == null) continue;

      virtualOffset += track.virtualPregap;
      final startLba = fileBaseLba + virtualOffset + track.indexOneInFile;
      tracks.add(
        _BinaryTrack(
          info: DiscTrackInfo(
            number: track.number,
            isData: track.isData,
            startLba: startLba,
            sectors: currentFileSectors - track.indexOneInFile,
          ),
          path: currentPath,
          sectorSize: track.sectorSize,
          dataOffset: track.dataOffset,
          fileStartSector: track.indexOneInFile,
        ),
      );
    }

    if (tracks.isEmpty) return null;
    return BinaryDiscImage._(tracks);
  }

  @override
  Future<Uint8List?> readSector(int trackIndex, int lba) async {
    if (trackIndex < 0 || trackIndex >= _tracks.length) return null;
    final track = _tracks[trackIndex];
    final withinTrack = lba - track.info.startLba;
    if (withinTrack < 0) return null;

    final rawSector = track.fileStartSector + withinTrack;
    final cached = _sliceFromWindow(trackIndex, track, rawSector);
    if (cached != null) return cached;

    // The window starts at the sector asked for rather than on a fixed grid:
    // reads run forwards from wherever a file begins, so this keeps every
    // sector of that file in as few reads as possible.
    final bytes = await OptimizedMd5Utils.readRange(
      track.path,
      rawSector * track.sectorSize,
      _windowSectors * track.sectorSize,
    );
    if (bytes.length < track.dataOffset + discSectorSize) {
      // Too short to hold even the sector that was asked for. Near the end of
      // a file a partial window is still usable, so this only fails the read
      // when the sector itself is not there.
      return null;
    }
    _window = bytes;
    _windowTrack = trackIndex;
    _windowFirstSector = rawSector;
    return _sliceFromWindow(trackIndex, track, rawSector);
  }

  /// The user bytes of [rawSector] if the current window covers it.
  ///
  /// Returns a view, not a copy. Windows are never written to and a refill
  /// allocates a new buffer, so views handed out earlier stay valid.
  Uint8List? _sliceFromWindow(
    int trackIndex,
    _BinaryTrack track,
    int rawSector,
  ) {
    final window = _window;
    if (window == null || _windowTrack != trackIndex) return null;

    final index = rawSector - _windowFirstSector;
    if (index < 0 || index >= _windowSectors) return null;

    final begin = index * track.sectorSize + track.dataOffset;
    final end = begin + discSectorSize;
    if (end > window.length) return null;

    return Uint8List.sublistView(window, begin, end);
  }

  @override
  Future<void> close() async {
    _window = null;
    _windowTrack = -1;
    _windowFirstSector = -1;
  }

  /// Finds the sector layout by looking for the ISO9660 volume descriptor that
  /// every one of these images has at sector 16.
  static Future<_SectorLayout?> _probeLayout(String path, int size) async {
    const candidates = [
      _SectorLayout(2048, 0), // .iso and MODE1/2048
      _SectorLayout(2352, 24), // MODE2/2352 — PlayStation and PC Engine CDs
      _SectorLayout(2352, 16), // MODE1/2352
      _SectorLayout(2336, 8), // MODE2/2336
    ];

    for (final candidate in candidates) {
      final offset = 16 * candidate.sectorSize + candidate.dataOffset;
      if (offset + discSectorSize > size) continue;
      final bytes = await OptimizedMd5Utils.readRange(path, offset, 8);
      if (bytes.length < 6) continue;
      if (bytes[1] == 0x43 && // C
          bytes[2] == 0x44 && // D
          bytes[3] == 0x30 && // 0
          bytes[4] == 0x30 && // 0
          bytes[5] == 0x31) {
        // 1
        return candidate;
      }
    }

    // No volume descriptor: a Sega CD or PC Engine disc carries its own header
    // instead of a filesystem, so fall back to the sector size the file size
    // divides evenly into.
    if (size % 2352 == 0) return const _SectorLayout(2352, 16);
    if (size % 2048 == 0) return const _SectorLayout(2048, 0);
    return null;
  }

  /// Resolves a file named by a cue sheet, next to the sheet itself.
  static Future<String?> _resolveSibling(String cuePath, String name) async {
    final candidate = resolveDiscSibling(cuePath, name);
    if (await OptimizedMd5Utils.fileExists(candidate)) return candidate;

    // Sheets that were renamed with their binary keep pointing at the old name.
    // Trying the sheet's own name with the referenced extension recovers the
    // common case without listing the directory.
    final dot = name.lastIndexOf('.');
    if (dot > 0) {
      final cueDot = cuePath.lastIndexOf('.');
      if (cueDot > 0) {
        final renamed = cuePath.substring(0, cueDot) + name.substring(dot);
        if (await OptimizedMd5Utils.fileExists(renamed)) return renamed;
      }
    }
    return null;
  }
}

class _BinaryTrack {
  final DiscTrackInfo info;
  final String path;
  final int sectorSize;
  final int dataOffset;
  final int fileStartSector;

  const _BinaryTrack({
    required this.info,
    required this.path,
    required this.sectorSize,
    required this.dataOffset,
    required this.fileStartSector,
  });
}

class _SectorLayout {
  final int sectorSize;
  final int dataOffset;

  const _SectorLayout(this.sectorSize, this.dataOffset);
}
