import '../../services/logger_service.dart';
import 'disc_image.dart';

/// Where a file lives on a disc: the sector it starts at and how long it is.
class IsoFile {
  /// The file's first sector, as the disc addresses it.
  final int sector;

  /// The file's length in bytes, from its directory record.
  final int size;

  const IsoFile(this.sector, this.size);
}

/// Just enough ISO9660 to find a file, which is all RetroAchievements hashing
/// needs: it identifies a disc game by its boot executable, so the filesystem
/// is a means of locating one file and never of listing the disc.
///
/// Follows rcheevos' reader deliberately, including its quirks — the volume
/// descriptor is read relative to the track's start while directory records are
/// taken as disc-absolute — because matching RetroAchievements means producing
/// the same answer it does, not the most correct one.
class Iso9660 {
  static final _log = LoggerService.instance;

  /// The identifier bytes 1..5 of every ISO9660 volume descriptor.
  static const List<int> _cd001 = [0x43, 0x44, 0x30, 0x30, 0x31];

  /// Whether [buffer] holds a volume descriptor rather than arbitrary bytes.
  static bool _startsWithCd001(List<int> buffer) {
    for (var i = 0; i < _cd001.length; i++) {
      if (buffer[1 + i] != _cd001[i]) return false;
    }
    return true;
  }

  /// Finds [path] on [track], where `\` separates directories, e.g.
  /// `PSP_GAME\SYSDIR\EBOOT.BIN`. Returns null when it is not there.
  static Future<IsoFile?> findFile(DiscTrack track, String path) async {
    var name = path.startsWith('\\') ? path.substring(1) : path;

    var directorySector = 0;
    var directorySectors = 1;

    final separator = name.lastIndexOf('\\');
    if (separator >= 0) {
      final parent = await findFile(track, name.substring(0, separator));
      if (parent == null) return null;
      directorySector = parent.sector;
      // A directory record's size covers its whole extent, which may be more
      // than one sector on a disc with many files.
      directorySectors = parent.size <= 0
          ? 1
          : (parent.size + discSectorSize - 1) ~/ discSectorSize;
      name = name.substring(separator + 1);
    } else {
      final root = await _readRootDirectory(track);
      if (root == null) return null;
      directorySector = root.sector;
      directorySectors = root.size;
    }

    return _findInDirectory(track, directorySector, directorySectors, name);
  }

  /// Reads the primary volume descriptor and returns the root directory's
  /// sector, with its length expressed in sectors.
  static Future<IsoFile?> _readRootDirectory(DiscTrack track) async {
    final buffer = await track.read(track.info.startLba + 16);
    // The root directory record ends 190 bytes in; a shorter read cannot
    // answer, and reading past it would throw rather than fail.
    if (buffer == null || buffer.length < 190) return null;

    // Every ISO9660 volume descriptor names the standard it follows, and
    // sector 16 is where the set begins. Without this check there is nothing
    // to tell a volume descriptor from any other 2048 bytes, so a container
    // read at the wrong offset — or a sector that is simply not a descriptor —
    // yields a plausible-looking root pointer into the middle of the disc, and
    // the walk below spends its time parsing game data as directory records.
    if (!_startsWithCd001(buffer)) {
      _log.w('RA disc: sector 16 is not an ISO9660 volume descriptor');
      return null;
    }

    // The root directory record sits 156 bytes into the descriptor; its extent
    // is 2 bytes into that, and its length 10 bytes in, both little-endian.
    final sector = buffer[158] | (buffer[159] << 8) | (buffer[160] << 16);
    if (sector <= 0) return null;

    final blockSize = buffer[128] | (buffer[129] << 8);
    if (blockSize <= 0) return IsoFile(sector, 1);

    final extentLength =
        buffer[166] |
        (buffer[167] << 8) |
        (buffer[168] << 16) |
        (buffer[169] << 24);
    final sectors = extentLength ~/ blockSize;
    return IsoFile(sector, sectors < 1 ? 1 : sectors);
  }

  /// The fixed part of a directory record, before its name.
  static const int _minimumRecordLength = 33;

  /// Scans a directory extent for [name].
  static Future<IsoFile?> _findInDirectory(
    DiscTrack track,
    int firstSector,
    int sectorCount,
    String name,
  ) async {
    final wanted = name.toUpperCase();
    var sector = firstSector;
    var remaining = sectorCount < 1 ? 1 : sectorCount;

    while (remaining > 0) {
      final buffer = await track.read(sector);
      if (buffer == null) return null;

      var offset = 0;
      while (offset < buffer.length) {
        final recordLength = buffer[offset];
        // A zero length is the end of the records in this sector; the extent
        // may still continue in the next one. So is anything shorter than the
        // 33-byte fixed part of a record, which cannot be one — and reading
        // that part on the strength of the declared length alone is how a
        // sector of non-record bytes walks off the end of the buffer.
        if (recordLength < _minimumRecordLength) break;
        if (offset + recordLength > buffer.length) break;

        final nameLength = buffer[offset + 32];
        if (nameLength > 0 && offset + 33 + nameLength <= buffer.length) {
          final recordName = String.fromCharCodes(
            buffer,
            offset + 33,
            offset + 33 + nameLength,
          ).toUpperCase();
          // Files carry a `;1` version suffix that callers do not write.
          final matches =
              recordName == wanted ||
              (recordName.length > wanted.length &&
                  recordName.startsWith(wanted) &&
                  recordName[wanted.length] == ';');
          if (matches) {
            final extent =
                buffer[offset + 2] |
                (buffer[offset + 3] << 8) |
                (buffer[offset + 4] << 16);
            final size =
                buffer[offset + 10] |
                (buffer[offset + 11] << 8) |
                (buffer[offset + 12] << 16) |
                (buffer[offset + 13] << 24);
            return IsoFile(extent, size);
          }
        }

        offset += recordLength;
      }

      sector++;
      remaining--;
    }

    return null;
  }
}
