/// Synthetic disc fixtures: an ISO9660 layout built a sector at a time, for
/// the tests that need one in memory and the tests that need one on disk.
library;

import 'dart:typed_data';

import 'package:neostation/utils/disc/disc_image.dart';

/// A disc built in memory, one sector at a time.
///
/// The console hashers only ever ask for sectors, so a synthetic ISO9660 layout
/// exercises the whole chain — directory walk, executable lookup, hashing — with
/// no file and no container. What it cannot check is that a real `.chd` yields
/// these sectors; that is the CHD reader's job and needs real discs.
class FakeDiscImage extends DiscImage {
  final Map<int, Uint8List> sectors;

  @override
  final List<DiscTrackInfo> tracks;

  FakeDiscImage(this.sectors, {int startLba = 0, bool isData = true})
    : tracks = [
        DiscTrackInfo(
          number: 1,
          isData: isData,
          startLba: startLba,
          sectors: 10000,
        ),
      ];

  /// A disc of several tracks, for the consoles whose hash depends on which
  /// track it reads.
  ///
  /// Sectors are still addressed disc-absolutely, the way an ISO9660 record
  /// numbers them, so a track's own start is what a reader has to subtract.
  FakeDiscImage.multiTrack({
    required List<({int number, bool isData, int startLba})> tracks,
    required this.sectors,
  }) : tracks = tracks
           .map(
             (track) => DiscTrackInfo(
               number: track.number,
               isData: track.isData,
               startLba: track.startLba,
               sectors: 10000,
             ),
           )
           .toList();

  @override
  Future<Uint8List?> readSector(int trackIndex, int lba) async => sectors[lba];

  @override
  Future<void> close() async {}
}

/// Builds a sector of [size] bytes, zero-padded.
Uint8List sector([List<int> content = const []]) {
  final data = Uint8List(discSectorSize);
  data.setRange(0, content.length, content);
  return data;
}

void writeUint32LE(Uint8List target, int offset, int value) {
  target[offset] = value & 0xFF;
  target[offset + 1] = (value >> 8) & 0xFF;
  target[offset + 2] = (value >> 16) & 0xFF;
  target[offset + 3] = (value >> 24) & 0xFF;
}

/// A primary volume descriptor pointing at a root directory.
Uint8List volumeDescriptor({required int rootSector, required int rootSize}) {
  final data = sector();
  data[0] = 1;
  data.setRange(1, 6, 'CD001'.codeUnits);
  data[6] = 1;
  // Logical block size.
  data[128] = 0x00;
  data[129] = 0x08;
  // Root directory record, 156 bytes in.
  data[156] = 34;
  writeUint32LE(data, 158, rootSector);
  writeUint32LE(data, 166, rootSize);
  data[188] = 1;
  return data;
}

/// A directory extent listing [entries] as `name -> (sector, size)`.
List<Uint8List> directory(Map<String, List<int>> entries) {
  final sectors = <Uint8List>[];
  var current = sector();
  var offset = 0;

  for (final entry in entries.entries) {
    final name = entry.key.codeUnits;
    var length = 33 + name.length;
    if (length.isOdd) length++;

    if (offset + length > discSectorSize) {
      sectors.add(current);
      current = sector();
      offset = 0;
    }

    current[offset] = length;
    writeUint32LE(current, offset + 2, entry.value[0]);
    writeUint32LE(current, offset + 10, entry.value[1]);
    current[offset + 32] = name.length;
    current.setRange(offset + 33, offset + 33 + name.length, name);
    offset += length;
  }

  sectors.add(current);
  return sectors;
}

/// A PS-X EXE whose header states [payloadBytes] bytes beyond the header.
Uint8List psxExecutableHeader(int payloadBytes) {
  final data = sector();
  data.setRange(0, 8, 'PS-X EXE'.codeUnits);
  writeUint32LE(data, 28, payloadBytes);
  return data;
}
