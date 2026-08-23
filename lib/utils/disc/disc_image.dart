import 'dart:typed_data';

/// Bytes of user data in a data sector, whatever the container wraps it in.
const int discSectorSize = 2048;

/// One track of a disc's table of contents.
class DiscTrackInfo {
  /// The track number the disc itself uses, counting from 1.
  final int number;

  /// Whether the track carries data rather than audio.
  final bool isData;

  /// The track's first sector as the disc addresses it.
  ///
  /// A filesystem's own sector numbers are disc-absolute, so this is what turns
  /// one into an offset inside the track.
  final int startLba;

  /// Readable sectors in the track.
  final int sectors;

  const DiscTrackInfo({
    required this.number,
    required this.isData,
    required this.startLba,
    required this.sectors,
  });
}

/// A disc image opened for reading, whatever container it arrived in.
///
/// Everything above this — ISO9660, the per-console hashing — works in terms of
/// sectors, so a `.chd` needing native decompression and a plain `.iso` that
/// needs nothing look the same to it.
abstract class DiscImage {
  /// The disc's tracks, in the order the image stores them.
  List<DiscTrackInfo> get tracks;

  /// The user data of disc-absolute sector [lba] within [trackIndex], or null
  /// if there is no such sector.
  Future<Uint8List?> readSector(int trackIndex, int lba);

  /// Releases whatever the image holds open.
  Future<void> close();

  /// The index of the first data track, or -1 when the disc has none.
  int get firstDataTrackIndex {
    for (var i = 0; i < tracks.length; i++) {
      if (tracks[i].isData) return i;
    }
    return -1;
  }
}

/// A track bound to the image it came from, which is how the console hashers
/// want to work: they open one track and then think only in sector numbers.
class DiscTrack {
  final DiscImage image;
  final int index;

  const DiscTrack(this.image, this.index);

  DiscTrackInfo get info => image.tracks[index];

  /// The user data of disc-absolute sector [lba], or null.
  Future<Uint8List?> read(int lba) => image.readSector(index, lba);
}
