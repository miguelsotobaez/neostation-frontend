import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/disc/disc_image.dart';
import 'package:neostation/utils/disc/iso9660.dart';
import 'package:neostation/utils/disc/ra_disc_hasher.dart';

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

void main() {
  group('ISO9660 lookup', () {
    test(
      'finds a file in the root directory, version suffix and all',
      () async {
        final image = FakeDiscImage({
          16: volumeDescriptor(rootSector: 20, rootSize: 2048),
          20: directory({
            'SYSTEM.CNF;1': [22, 100],
            'SLUS_007.27;1': [24, 4096],
          }).first,
        });

        final found = await Iso9660.findFile(
          DiscTrack(image, 0),
          'SLUS_007.27',
        );

        expect(found, isNotNull);
        expect(found!.sector, 24);
        expect(found.size, 4096);
      },
    );

    test('walks a directory that spans more than one sector', () async {
      // Enough entries to overflow the first sector, with the wanted file last.
      final entries = <String, List<int>>{
        for (var i = 0; i < 60; i++) 'FILLER_ENTRY_NUMBER_$i.DAT;1': [100, 1],
        'TARGET.BIN;1': [999, 42],
      };
      final extent = directory(entries);
      expect(extent.length, greaterThan(1));

      final image = FakeDiscImage({
        16: volumeDescriptor(
          rootSector: 20,
          rootSize: extent.length * discSectorSize,
        ),
        for (var i = 0; i < extent.length; i++) 20 + i: extent[i],
      });

      final found = await Iso9660.findFile(DiscTrack(image, 0), 'TARGET.BIN');

      expect(found?.sector, 999);
    });

    test('finds a file down a path of directories', () async {
      final image = FakeDiscImage({
        16: volumeDescriptor(rootSector: 20, rootSize: 2048),
        20: directory({
          'PSP_GAME': [30, 2048],
        }).first,
        30: directory({
          'PARAM.SFO;1': [40, 512],
          'SYSDIR': [50, 2048],
        }).first,
        50: directory({
          'EBOOT.BIN;1': [60, 3000],
        }).first,
      });

      final found = await Iso9660.findFile(
        DiscTrack(image, 0),
        'PSP_GAME\\SYSDIR\\EBOOT.BIN',
      );

      expect(found?.sector, 60);
      expect(found?.size, 3000);
    });

    test('reads the volume descriptor relative to the track start', () async {
      // A data track that does not start at sector 0 — the descriptor is 16
      // sectors into the track, not 16 into the disc.
      final image = FakeDiscImage({
        1016: volumeDescriptor(rootSector: 1020, rootSize: 2048),
        1020: directory({
          'BOOT.BIN;1': [1030, 8],
        }).first,
      }, startLba: 1000);

      final found = await Iso9660.findFile(DiscTrack(image, 0), 'BOOT.BIN');

      expect(found?.sector, 1030);
    });
  });

  group('PlayStation hashing', () {
    /// A disc whose SYSTEM.CNF boots [exeName], with an executable of
    /// [payloadBytes] beyond its header.
    FakeDiscImage playstationDisc({
      required String bootLine,
      required String exeName,
      required int payloadBytes,
      bool withPsxHeader = true,
      int directorySize = 4096,
    }) {
      final exeSectors = <int, Uint8List>{};
      final header = withPsxHeader
          ? psxExecutableHeader(payloadBytes)
          : sector([1, 2, 3, 4]);
      exeSectors[24] = header;
      // Payload sectors, each filled with a recognisable byte.
      for (var i = 0; i * discSectorSize < payloadBytes; i++) {
        exeSectors[25 + i] = sector(List.filled(64, i + 1));
      }

      return FakeDiscImage({
        16: volumeDescriptor(rootSector: 20, rootSize: 2048),
        20: directory({
          'SYSTEM.CNF;1': [22, 100],
          '$exeName;1': [24, directorySize],
        }).first,
        22: sector(bootLine.codeUnits),
        ...exeSectors,
      });
    }

    test('hashes the executable name together with its contents', () async {
      final image = playstationDisc(
        bootLine: 'BOOT = cdrom:\\SLUS_007.27;1\r\nTCB = 4\r\n',
        exeName: 'SLUS_007.27',
        payloadBytes: 2048,
      );

      final hash = await RaDiscHasher.hashPlaystation(DiscTrack(image, 0));

      // The header states 2048 payload bytes, and the hash covers the header
      // as well — so name + two whole sectors.
      final expected = crypto.md5.convert([
        ...'SLUS_007.27'.codeUnits,
        ...(await image.readSector(0, 24))!,
        ...(await image.readSector(0, 25))!,
      ]);
      expect(hash, expected.toString());
    });

    test(
      'takes the length from the PS-X EXE header, not the directory',
      () async {
        final withHeader = await RaDiscHasher.hashPlaystation(
          DiscTrack(
            playstationDisc(
              bootLine: 'BOOT = cdrom:\\SLUS_007.27;1\r\n',
              exeName: 'SLUS_007.27',
              payloadBytes: 2048,
              directorySize: 999999,
            ),
            0,
          ),
        );
        final sameHeaderDifferentDirectorySize =
            await RaDiscHasher.hashPlaystation(
              DiscTrack(
                playstationDisc(
                  bootLine: 'BOOT = cdrom:\\SLUS_007.27;1\r\n',
                  exeName: 'SLUS_007.27',
                  payloadBytes: 2048,
                  directorySize: 4096,
                ),
                0,
              ),
            );

        expect(withHeader, isNotNull);
        expect(withHeader, sameHeaderDifferentDirectorySize);
      },
    );

    test(
      'falls back to the directory size when the marker is missing',
      () async {
        final image = playstationDisc(
          bootLine: 'BOOT = cdrom:\\SLUS_007.27;1\r\n',
          exeName: 'SLUS_007.27',
          payloadBytes: 2048,
          withPsxHeader: false,
          directorySize: 2048,
        );

        final hash = await RaDiscHasher.hashPlaystation(DiscTrack(image, 0));

        final expected = crypto.md5.convert([
          ...'SLUS_007.27'.codeUnits,
          ...(await image.readSector(0, 24))!,
        ]);
        expect(hash, expected.toString());
      },
    );

    test('tolerates a boot line with no spaces around the equals', () async {
      final spaced = await RaDiscHasher.hashPlaystation(
        DiscTrack(
          playstationDisc(
            bootLine: 'BOOT = cdrom:\\SLUS_007.27;1\r\n',
            exeName: 'SLUS_007.27',
            payloadBytes: 2048,
          ),
          0,
        ),
      );
      final tight = await RaDiscHasher.hashPlaystation(
        DiscTrack(
          playstationDisc(
            bootLine: 'BOOT=cdrom:SLUS_007.27;1\r\n',
            exeName: 'SLUS_007.27',
            payloadBytes: 2048,
          ),
          0,
        ),
      );

      expect(spaced, isNotNull);
      expect(tight, spaced);
    });

    test('falls back to PSX.EXE when there is no SYSTEM.CNF', () async {
      final image = FakeDiscImage({
        16: volumeDescriptor(rootSector: 20, rootSize: 2048),
        20: directory({
          'PSX.EXE;1': [24, 2048],
        }).first,
        24: psxExecutableHeader(0),
      });

      final hash = await RaDiscHasher.hashPlaystation(DiscTrack(image, 0));

      final expected = crypto.md5.convert([
        ...'PSX.EXE'.codeUnits,
        ...(await image.readSector(0, 24))!,
      ]);
      expect(hash, expected.toString());
    });

    test('returns null when no executable can be located', () async {
      final image = FakeDiscImage({
        16: volumeDescriptor(rootSector: 20, rootSize: 2048),
        20: directory({
          'README.TXT;1': [24, 10],
        }).first,
      });

      expect(await RaDiscHasher.hashPlaystation(DiscTrack(image, 0)), isNull);
    });

    test('PlayStation 2 reads BOOT2 and the cdrom0 prefix', () async {
      final image = FakeDiscImage({
        16: volumeDescriptor(rootSector: 20, rootSize: 2048),
        20: directory({
          'SYSTEM.CNF;1': [22, 100],
          'SLUS_202.02;1': [24, 2048],
        }).first,
        22: sector('BOOT2 = cdrom0:\\SLUS_202.02;1\r\nVER=1.00\r\n'.codeUnits),
        24: sector([0x7F, 0x45, 0x4C, 0x46]),
      });

      final hash = await RaDiscHasher.hashPlaystation2(DiscTrack(image, 0));

      final expected = crypto.md5.convert([
        ...'SLUS_202.02'.codeUnits,
        ...(await image.readSector(0, 24))!,
      ]);
      expect(hash, expected.toString());
    });

    test('PlayStation 2 ignores a PS1 BOOT line', () async {
      final image = FakeDiscImage({
        16: volumeDescriptor(rootSector: 20, rootSize: 2048),
        20: directory({
          'SYSTEM.CNF;1': [22, 100],
        }).first,
        22: sector('BOOT = cdrom:\\SLUS_007.27;1\r\n'.codeUnits),
      });

      expect(await RaDiscHasher.hashPlaystation2(DiscTrack(image, 0)), isNull);
    });
  });

  group('PSP hashing', () {
    test('hashes PARAM.SFO then EBOOT.BIN, and nothing else', () async {
      final image = FakeDiscImage({
        16: volumeDescriptor(rootSector: 20, rootSize: 2048),
        20: directory({
          'PSP_GAME': [30, 2048],
        }).first,
        30: directory({
          'PARAM.SFO;1': [40, 100],
          'SYSDIR': [50, 2048],
        }).first,
        40: sector('PARAM'.codeUnits),
        50: directory({
          'EBOOT.BIN;1': [60, 200],
        }).first,
        60: sector('EBOOT'.codeUnits),
      });

      final hash = await RaDiscHasher.hashPsp(DiscTrack(image, 0));

      final expected = crypto.md5.convert([
        ...(await image.readSector(0, 40))!.sublist(0, 100),
        ...(await image.readSector(0, 60))!.sublist(0, 200),
      ]);
      expect(hash, expected.toString());
    });

    test('returns null on a disc that is not a PSP game', () async {
      final image = FakeDiscImage({
        16: volumeDescriptor(rootSector: 20, rootSize: 2048),
        20: directory({
          'SYSTEM.CNF;1': [22, 100],
        }).first,
      });

      expect(await RaDiscHasher.hashPsp(DiscTrack(image, 0)), isNull);
    });
  });

  group('Sega CD and Saturn hashing', () {
    test('hashes the first 512 bytes of the disc', () async {
      final header = sector([
        ...'SEGADISCSYSTEM  '.codeUnits,
        ...List.filled(64, 0xAB),
      ]);
      final image = FakeDiscImage({0: header});

      final hash = await RaDiscHasher.hashSegaDisc(DiscTrack(image, 0));

      expect(hash, crypto.md5.convert(header.sublist(0, 512)).toString());
    });

    test('accepts a Saturn header', () async {
      final image = FakeDiscImage({0: sector('SEGA SEGASATURN '.codeUnits)});

      expect(await RaDiscHasher.hashSegaDisc(DiscTrack(image, 0)), isNotNull);
    });

    test('rejects a disc with neither header', () async {
      final image = FakeDiscImage({0: sector('NOT A SEGA DISC'.codeUnits)});

      expect(await RaDiscHasher.hashSegaDisc(DiscTrack(image, 0)), isNull);
    });
  });

  group('PC Engine CD hashing', () {
    test('hashes the disc title and the program it points at', () async {
      final header = sector();
      // Program at sector 100, two sectors long.
      header[0] = 0;
      header[1] = 0;
      header[2] = 100;
      header[3] = 2;
      header.setRange(32, 55, 'PC Engine CD-ROM SYSTEM'.codeUnits);
      header.setRange(106, 128, 'GAME TITLE            '.codeUnits);

      final image = FakeDiscImage({
        1: header,
        100: sector(List.filled(32, 0x11)),
        101: sector(List.filled(32, 0x22)),
      });

      final hash = await RaDiscHasher.hashPcEngineCd(DiscTrack(image, 0));

      final expected = crypto.md5.convert([
        ...header.sublist(106, 128),
        ...(await image.readSector(0, 100))!,
        ...(await image.readSector(0, 101))!,
      ]);
      expect(hash, expected.toString());
    });

    test('reads the header relative to the track start', () async {
      final header = sector();
      header[2] = 100;
      header[3] = 1;
      header.setRange(32, 55, 'PC Engine CD-ROM SYSTEM'.codeUnits);

      // A PC Engine CD leads with an audio track, so its data track starts
      // well into the disc and the program sector is relative to it.
      final image = FakeDiscImage({
        1001: header,
        1100: sector(List.filled(32, 0x33)),
      }, startLba: 1000);

      final hash = await RaDiscHasher.hashPcEngineCd(DiscTrack(image, 0));

      final expected = crypto.md5.convert([
        ...header.sublist(106, 128),
        ...(await image.readSector(0, 1100))!,
      ]);
      expect(hash, expected.toString());
    });

    test('falls back to BOOT.BIN on a GameExpress disc', () async {
      final image = FakeDiscImage({
        1: sector('nothing here'.codeUnits),
        16: volumeDescriptor(rootSector: 20, rootSize: 2048),
        20: directory({
          'BOOT.BIN;1': [24, 300],
        }).first,
        24: sector(List.filled(300, 0x44)),
      });

      final hash = await RaDiscHasher.hashPcEngineCd(DiscTrack(image, 0));

      final expected = crypto.md5.convert(
        (await image.readSector(0, 24))!.sublist(0, 300),
      );
      expect(hash, expected.toString());
    });
  });
}
