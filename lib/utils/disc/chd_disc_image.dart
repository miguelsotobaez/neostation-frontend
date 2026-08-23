import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_chd/flutter_chd.dart';

import '../../services/logger_service.dart';
import '../../services/saf_directory_service.dart';
import 'disc_image.dart';

/// A CHD disc image, read through the vendored libchdr.
///
/// CHD is what almost every disc ROM in a real library is stored as, and it is
/// the one container that cannot be read without native code.
class ChdDiscImage extends DiscImage {
  static final _log = LoggerService.instance;

  final ChdDisc _disc;

  ChdDiscImage._(this._disc);

  /// Opens the CHD at [path], or returns null if it cannot be read.
  ///
  /// On Android a ROM path is a SAF `content://` URI that libchdr cannot open,
  /// so the platform is asked for a file descriptor instead.
  static Future<ChdDiscImage?> open(String path) async {
    try {
      if (Platform.isAndroid && path.startsWith('content://')) {
        final fd = await SafDirectoryService.openFileDescriptor(path);
        if (fd == null) {
          _log.w('CHD: no file descriptor for $path');
          return null;
        }
        return ChdDiscImage._(ChdDisc.openFd(fd));
      }
      return ChdDiscImage._(ChdDisc.open(path));
    } on ChdException catch (e) {
      _log.w('CHD: $e');
      return null;
    } catch (e) {
      _log.e('CHD: failed to open $path: $e');
      return null;
    }
  }

  @override
  late final List<DiscTrackInfo> tracks = _disc.tracks
      .map(
        (track) => DiscTrackInfo(
          number: track.number,
          isData: track.isData,
          startLba: track.startLba,
          sectors: track.sectors,
        ),
      )
      .toList(growable: false);

  @override
  Future<Uint8List?> readSector(int trackIndex, int lba) async {
    if (trackIndex < 0 || trackIndex >= tracks.length) return null;
    final withinTrack = lba - tracks[trackIndex].startLba;
    if (withinTrack < 0) return null;
    return _disc.readSector(trackIndex, withinTrack);
  }

  @override
  Future<void> close() async => _disc.close();
}
