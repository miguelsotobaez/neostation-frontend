import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/models/ra_hash_policy.dart';
import 'package:neostation/utils/disc/cso_disc_image.dart';
import 'package:neostation/utils/disc/disc_image.dart';
import 'package:neostation/utils/disc/ra_disc_hash.dart';

import 'disc_fixtures.dart';

/// How a block was written, so a test can force the shapes a real writer only
/// produces for certain content.
enum BlockStorage {
  /// Deflate, falling back to storing a block that would only grow.
  compressed,

  /// Stored, and flagged as stored.
  plain,

  /// Stored, but left flagged as compressed — which is what some writers do
  /// with a block that would not compress.
  plainUnflagged,
}

/// Writes [iso] as a CISO image, the way a real compressor would lay one out.
///
/// The header is 24 bytes, then one 32-bit entry per block plus a terminator.
/// An entry holds the block's offset shifted right by [align] — so [align]
/// above zero pads every block out to that boundary — and its top bit says the
/// block was stored rather than deflated.
Uint8List buildCso(
  Uint8List iso, {
  int blockSize = 2048,
  int align = 0,
  BlockStorage storage = BlockStorage.compressed,
}) {
  final blockCount = (iso.length + blockSize - 1) ~/ blockSize;
  final chunks = <Uint8List>[];
  final plain = <bool>[];

  for (var i = 0; i < blockCount; i++) {
    final start = i * blockSize;
    final end = min(start + blockSize, iso.length);
    final raw = Uint8List.sublistView(iso, start, end);

    if (storage != BlockStorage.compressed) {
      chunks.add(raw);
      plain.add(storage == BlockStorage.plain);
      continue;
    }
    final deflated = Uint8List.fromList(
      ZLibEncoder(raw: true, level: 9).convert(raw),
    );
    final fits = deflated.length < raw.length;
    chunks.add(fits ? deflated : raw);
    plain.add(!fits);
  }

  final unit = 1 << align;
  int alignUp(int value) => (value + unit - 1) ~/ unit * unit;

  final offsets = <int>[];
  var cursor = alignUp(24 + (blockCount + 1) * 4);
  for (final chunk in chunks) {
    offsets.add(cursor);
    cursor = alignUp(cursor + chunk.length);
  }
  offsets.add(cursor);

  final out = Uint8List(cursor);
  final view = ByteData.sublistView(out);
  out.setRange(0, 4, 'CISO'.codeUnits);
  view.setUint32(4, 24, Endian.little);
  view.setUint64(8, iso.length, Endian.little);
  view.setUint32(0x10, blockSize, Endian.little);
  out[0x14] = 1;
  out[0x15] = align;

  for (var i = 0; i < blockCount; i++) {
    final entry = (offsets[i] >> align) | (plain[i] ? 0x80000000 : 0);
    view.setUint32(24 + i * 4, entry, Endian.little);
    out.setRange(offsets[i], offsets[i] + chunks[i].length, chunks[i]);
  }
  view.setUint32(
    24 + blockCount * 4,
    offsets[blockCount] >> align,
    Endian.little,
  );

  return out;
}

/// A flat 2048-byte-sector image of [sectorCount] sectors.
///
/// Each sector leads with its own number and carries content that compresses
/// some of the way but not all of it, so a real CISO of this has both the
/// deflated blocks and the window refills a real one would.
Uint8List buildFlatIso(int sectorCount, {int seed = 7}) {
  final random = Random(seed);
  final bytes = Uint8List(sectorCount * discSectorSize);
  final view = ByteData.sublistView(bytes);
  for (var lba = 0; lba < sectorCount; lba++) {
    final base = lba * discSectorSize;
    for (var i = 4; i < discSectorSize; i++) {
      bytes[base + i] = random.nextInt(64);
    }
    view.setUint32(base, lba, Endian.little);
  }
  return bytes;
}

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('neostation_cso_test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<String> write(String name, Uint8List bytes) async {
    final path = '${temp.path}/$name';
    await File(path).writeAsBytes(bytes);
    return path;
  }

  /// Reads every sector of [image] back and compares it with [iso].
  Future<void> expectMatchesIso(DiscImage image, Uint8List iso) async {
    for (var lba = 0; lba < iso.length ~/ discSectorSize; lba++) {
      final sector = await image.readSector(0, lba);
      expect(sector, isNotNull, reason: 'sector $lba is missing');
      expect(
        sector,
        orderedEquals(
          Uint8List.sublistView(
            iso,
            lba * discSectorSize,
            (lba + 1) * discSectorSize,
          ),
        ),
        reason: 'sector $lba differs',
      );
    }
  }

  group('CISO images', () {
    test('reads every sector of a one-sector-per-block image', () async {
      final iso = buildFlatIso(64);
      final path = await write('game.cso', buildCso(iso));

      final image = await CsoDiscImage.open(path);

      expect(image, isNotNull);
      expect(image!.tracks.single.number, 1);
      expect(image.tracks.single.startLba, 0);
      expect(image.tracks.single.sectors, 64);
      await expectMatchesIso(image, iso);
      await image.close();
    });

    test('slices sectors out of a 16 KiB block', () async {
      // Eight sectors to a block, so most reads are served from the block that
      // the read before them inflated.
      final iso = buildFlatIso(64);
      final path = await write('game.cso', buildCso(iso, blockSize: 16384));

      final image = await CsoDiscImage.open(path);

      expect(image, isNotNull);
      await expectMatchesIso(image!, iso);
      await image.close();
    });

    test('reads blocks that were stored rather than deflated', () async {
      final iso = buildFlatIso(32);
      final path = await write(
        'game.cso',
        buildCso(iso, storage: BlockStorage.plain),
      );

      final image = await CsoDiscImage.open(path);

      expect(image, isNotNull);
      await expectMatchesIso(image!, iso);
      await image.close();
    });

    test('reads a stored block that was left flagged as compressed', () async {
      // Writers in the wild do this with a block that would not compress, and
      // inflating it produces nothing.
      final iso = buildFlatIso(32);
      final path = await write(
        'game.cso',
        buildCso(iso, storage: BlockStorage.plainUnflagged),
      );

      final image = await CsoDiscImage.open(path);

      expect(image, isNotNull);
      await expectMatchesIso(image!, iso);
      await image.close();
    });

    test('reads past the padding an alignment leaves after a block', () async {
      // Alignment pads each block out, so the bytes handed to zlib run past the
      // end of the deflate stream.
      final iso = buildFlatIso(32);
      final path = await write('game.cso', buildCso(iso, align: 4));

      final image = await CsoDiscImage.open(path);

      expect(image, isNotNull);
      await expectMatchesIso(image!, iso);
      await image.close();
    });

    test('reads an image larger than one window', () async {
      // Blocks are fetched a megabyte at a time; this image compresses to more
      // than one window, so the sequential read has to refill it.
      final iso = buildFlatIso(1600);
      final compressed = buildCso(iso);
      expect(compressed.length, greaterThan(1 << 20));
      final path = await write('game.cso', compressed);

      final image = await CsoDiscImage.open(path);

      expect(image, isNotNull);
      await expectMatchesIso(image!, iso);
      await image.close();
    });

    test('serves a sector again after the window moved on', () async {
      // The ISO9660 walk comes back to the volume descriptor and the directory
      // extents after streaming a file, which is a backwards seek.
      final iso = buildFlatIso(1600);
      final path = await write('game.cso', buildCso(iso));

      final image = await CsoDiscImage.open(path);
      expect(image, isNotNull);

      final first = await image!.readSector(0, 16);
      for (var lba = 0; lba < 1600; lba += 7) {
        await image.readSector(0, lba);
      }
      final again = await image.readSector(0, 16);

      expect(again, orderedEquals(first!));
      await image.close();
    });

    test('reads a header that declares version zero', () async {
      // CisoJr4Droid, which is what a conversion done on the handheld itself
      // comes out of, leaves the version byte at zero.
      final iso = buildFlatIso(32);
      final bytes = buildCso(iso);
      bytes[0x14] = 0;
      final path = await write('game.cso', bytes);

      final image = await CsoDiscImage.open(path);

      expect(image, isNotNull);
      await expectMatchesIso(image!, iso);
      await image.close();
    });

    test('refuses a file that is not a CISO image', () async {
      final path = await write('game.cso', buildFlatIso(4));

      expect(await CsoDiscImage.open(path), isNull);
    });

    test('refuses a version it does not know how to read', () async {
      // Version 2 mixes codecs per block.
      final bytes = buildCso(buildFlatIso(8));
      bytes[0x14] = 2;
      final path = await write('game.cso', bytes);

      expect(await CsoDiscImage.open(path), isNull);
    });

    test('refuses a block size that is not whole sectors', () async {
      final bytes = buildCso(buildFlatIso(8));
      ByteData.sublistView(bytes).setUint32(0x10, 1000, Endian.little);
      final path = await write('game.cso', bytes);

      expect(await CsoDiscImage.open(path), isNull);
    });

    test('refuses an image whose block index was truncated', () async {
      final bytes = buildCso(buildFlatIso(64));
      final path = await write('game.cso', bytes.sublist(0, 40));

      expect(await CsoDiscImage.open(path), isNull);
    });

    test('reads no sector past the end of the image', () async {
      final iso = buildFlatIso(8);
      final path = await write('game.cso', buildCso(iso));

      final image = await CsoDiscImage.open(path);

      expect(await image!.readSector(0, 8), isNull);
      expect(await image.readSector(0, -1), isNull);
      expect(await image.readSector(1, 0), isNull);
      await image.close();
    });
  });

  group('hashing a PSP disc', () {
    /// A flat ISO holding the two files a PSP hash covers.
    Uint8List pspIso() {
      final sectors = <int, Uint8List>{
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
      };

      final iso = Uint8List(80 * discSectorSize);
      for (final entry in sectors.entries) {
        iso.setRange(
          entry.key * discSectorSize,
          (entry.key + 1) * discSectorSize,
          entry.value,
        );
      }
      return iso;
    }

    test('gives a .cso the same hash as the .iso it was made from', () async {
      // The point of the whole reader: RetroAchievements registered the hash of
      // what is inside the container, and PPSSPP reports it from a `.cso`
      // because it reads one natively.
      final iso = pspIso();
      final isoPath = await write('game.iso', iso);
      final csoPath = await write('game.cso', buildCso(iso));

      final fromIso = await RaDiscHash.compute(RaHashAlgo.psp, isoPath);
      final fromCso = await RaDiscHash.compute(RaHashAlgo.psp, csoPath);

      expect(fromIso, isNotNull);
      expect(fromCso, fromIso);
    });

    test(
      'hashes a .ciso, which is the same format under another name',
      () async {
        final iso = pspIso();
        final isoPath = await write('game.iso', iso);
        final csoPath = await write(
          'game.ciso',
          buildCso(iso, blockSize: 16384),
        );

        expect(
          await RaDiscHash.compute(RaHashAlgo.psp, csoPath),
          await RaDiscHash.compute(RaHashAlgo.psp, isoPath),
        );
      },
    );

    test('is offered .cso and .ciso as containers it can hash', () {
      expect(RaDiscHash.canHash('/roms/psp/Game.cso'), isTrue);
      expect(RaDiscHash.canHash('/roms/psp/Game.CSO'), isTrue);
      expect(RaDiscHash.canHash('/roms/ps2/Game.ciso'), isTrue);
    });
  });
}
