/// Reads tracks and sectors out of a CHD disc image.
///
/// CHD is how essentially every disc-based ROM in a real library is stored, and
/// RetroAchievements identifies a disc game by hashing the executable inside its
/// filesystem — so a hash of the container file matches nothing. This package
/// supplies the one primitive that unlocks the rest: the 2048 bytes of user data
/// of a given logical sector of a given track.
///
/// The filesystem parsing on top of it is deliberately not here; it is shared
/// with plain `.iso` and `.cue`/`.bin` images that need no native code at all.
library;

import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

const String _libName = 'flutter_chd';

/// An absolute path to load the native library from instead of the bundled
/// one. Null in an app, where Flutter ships the library beside the binary.
///
/// This exists for tests: `flutter test` runs in the Dart VM with no plugin
/// build, so a test that wants to exercise the reader has to build the library
/// itself and say where it put it. Set it before the first call.
String? chdLibraryOverridePath;

/// The dynamic library holding the native reader.
final DynamicLibrary _dylib = () {
  final override = chdLibraryOverridePath;
  if (override != null) return DynamicLibrary.open(override);
  if (Platform.isMacOS || Platform.isIOS) {
    return DynamicLibrary.open('$_libName.framework/$_libName');
  }
  if (Platform.isAndroid || Platform.isLinux) {
    return DynamicLibrary.open('lib$_libName.so');
  }
  if (Platform.isWindows) {
    return DynamicLibrary.open('$_libName.dll');
  }
  throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
}();

// Six symbols, all flat integers and byte buffers, so the bindings are written
// out rather than generated: there is no struct or callback layout to keep in
// step with the header, and this way the package needs no ffigen toolchain.
final _nchdOpen = _dylib.lookupFunction<
    Pointer<Void> Function(Pointer<Utf8>, Pointer<Int32>),
    Pointer<Void> Function(Pointer<Utf8>, Pointer<Int32>)>('nchd_open');

final _nchdOpenFd = _dylib.lookupFunction<
    Pointer<Void> Function(Int32, Pointer<Int32>),
    Pointer<Void> Function(int, Pointer<Int32>)>('nchd_open_fd');

final _nchdTrackCount = _dylib
    .lookupFunction<Int32 Function(Pointer<Void>), int Function(Pointer<Void>)>(
  'nchd_track_count',
);

final _nchdTrackField = _dylib.lookupFunction<
    Int32 Function(Pointer<Void>, Int32, Int32),
    int Function(Pointer<Void>, int, int)>('nchd_track_field');

final _nchdReadSector = _dylib.lookupFunction<
    Int32 Function(Pointer<Void>, Int32, Uint32, Pointer<Uint8>),
    int Function(Pointer<Void>, int, int, Pointer<Uint8>)>('nchd_read_sector');

final _nchdClose = _dylib.lookupFunction<Void Function(Pointer<Void>),
    void Function(Pointer<Void>)>('nchd_close');

/// Bytes of user data in a data sector.
const int chdSectorSize = 2048;

/// Why a CHD could not be opened.
enum ChdOpenError {
  /// The file is missing, unreadable, or not a CHD at all.
  open,

  /// A CHD, but one describing no readable track — a hard-disk image, or a
  /// disc whose sectors are neither CD frames nor plain 2048-byte ones.
  noTracks,

  /// Compressed with a codec this build cannot decode.
  unsupported,

  /// Out of memory.
  memory;

  static ChdOpenError _fromCode(int code) => switch (code) {
        2 => ChdOpenError.noTracks,
        3 => ChdOpenError.unsupported,
        4 => ChdOpenError.memory,
        _ => ChdOpenError.open,
      };
}

/// Thrown when a CHD cannot be opened.
class ChdException implements Exception {
  /// Why the open failed.
  final ChdOpenError error;

  /// What was being opened, for the log.
  final String target;

  const ChdException(this.error, this.target);

  @override
  String toString() => 'ChdException(${error.name}): $target';
}

/// One track of a CHD's table of contents.
class ChdTrack {
  /// The track number the disc itself uses, counting from 1.
  final int number;

  /// Whether the track carries data rather than audio.
  final bool isData;

  /// Whether the track's sectors are MODE2, whose user data sits behind a
  /// subheader. Callers that read raw sectors do not need this — the reader
  /// already accounts for it — but the console hashers use it to tell a
  /// PlayStation disc's layout from a PC Engine CD's.
  final bool isMode2;

  /// Readable sectors in the track, excluding any pregap stored in the file.
  final int sectors;

  /// The track's first sector as the disc addresses it.
  ///
  /// A filesystem's own sector numbers are disc-absolute, so a caller reading a
  /// data track that is not the first one subtracts this to get the index
  /// [ChdDisc.readSector] wants.
  final int startLba;

  const ChdTrack({
    required this.number,
    required this.isData,
    required this.isMode2,
    required this.sectors,
    required this.startLba,
  });
}

/// An open CHD disc image.
///
/// Not safe to share across isolates: it owns a native handle and a one-sector
/// scratch buffer. Open it where the hashing runs.
class ChdDisc {
  final Pointer<Void> _handle;
  final Pointer<Uint8> _buffer;
  bool _closed = false;

  ChdDisc._(this._handle, this._buffer);

  /// Opens the CHD at [path].
  ///
  /// Throws [ChdException] if it cannot be read.
  factory ChdDisc.open(String path) {
    final nativePath = path.toNativeUtf8();
    final errorOut = calloc<Int32>();
    try {
      final handle = _nchdOpen(nativePath, errorOut);
      if (handle == nullptr) {
        throw ChdException(ChdOpenError._fromCode(errorOut.value), path);
      }
      return ChdDisc._(handle, calloc<Uint8>(chdSectorSize));
    } finally {
      calloc.free(nativePath);
      calloc.free(errorOut);
    }
  }

  /// Opens a CHD from an already-open file descriptor, which this disc takes
  /// ownership of and closes with [close].
  ///
  /// Android ROM paths are SAF `content://` URIs with no filesystem path to
  /// open, but the platform hands out a descriptor for one.
  ///
  /// Throws [ChdException] if it cannot be read; the descriptor is closed
  /// either way.
  factory ChdDisc.openFd(int fd) {
    final errorOut = calloc<Int32>();
    try {
      final handle = _nchdOpenFd(fd, errorOut);
      if (handle == nullptr) {
        throw ChdException(ChdOpenError._fromCode(errorOut.value), 'fd $fd');
      }
      return ChdDisc._(handle, calloc<Uint8>(chdSectorSize));
    } finally {
      calloc.free(errorOut);
    }
  }

  /// The disc's tracks, in the order the image stores them.
  late final List<ChdTrack> tracks = List.generate(
    _nchdTrackCount(_handle),
    (index) => ChdTrack(
      number: _nchdTrackField(_handle, index, 0),
      isData: _nchdTrackField(_handle, index, 1) != 0,
      isMode2: _nchdTrackField(_handle, index, 1) == 2,
      sectors: _nchdTrackField(_handle, index, 2),
      startLba: _nchdTrackField(_handle, index, 3),
    ),
    growable: false,
  );

  /// The user data of logical sector [lba] of the track at [trackIndex], or
  /// null if there is no such sector or it could not be decompressed.
  ///
  /// The returned list is a copy, so it stays valid after the next read.
  Uint8List? readSector(int trackIndex, int lba) {
    if (_closed) return null;
    final read = _nchdReadSector(_handle, trackIndex, lba, _buffer);
    if (read != chdSectorSize) return null;
    return Uint8List.fromList(_buffer.asTypedList(chdSectorSize));
  }

  /// Releases the native handle. Safe to call more than once.
  void close() {
    if (_closed) return;
    _closed = true;
    _nchdClose(_handle);
    calloc.free(_buffer);
  }
}
