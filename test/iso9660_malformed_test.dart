import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/disc/disc_image.dart';
import 'package:neostation/utils/disc/iso9660.dart';

import 'ra_disc_hash_test.dart' show FakeDiscImage, directory, volumeDescriptor;

/// What the ISO9660 reader does when the bytes it is handed are not a
/// filesystem.
///
/// It reaches this state more often than a corrupt disc would suggest: a
/// container read at the wrong offset delivers perfectly good game data to a
/// reader that believes it is looking at a volume descriptor. Failing cleanly
/// there is the difference between "this disc has no executable on it" and an
/// exception the bulk pass records as a bare `error`.
void main() {
  DiscTrack trackOf(Map<int, Uint8List> sectors) =>
      DiscTrack(FakeDiscImage(sectors), 0);

  group('the volume descriptor', () {
    test('is rejected when sector 16 does not say CD001', () async {
      // Sector 16 as a mis-read container delivers it: real bytes, shifted, so
      // the identifier is gone but the rest still parses into a root pointer.
      final shifted = volumeDescriptor(rootSector: 20, rootSize: 2048);
      shifted[1] = 0x4F; // 'O' — what a 16-byte offset lands on

      final found = await Iso9660.findFile(
        trackOf({
          16: shifted,
          20: directory({
            'SLUS_202.02;1': [24, 2048],
          }).first,
        }),
        'SLUS_202.02',
      );

      expect(
        found,
        isNull,
        reason: 'without CD001 there is no reason to trust byte 158 either',
      );
    });

    test('still reads a descriptor that does say CD001', () async {
      final found = await Iso9660.findFile(
        trackOf({
          16: volumeDescriptor(rootSector: 20, rootSize: 2048),
          20: directory({
            'SLUS_202.02;1': [24, 2048],
          }).first,
        }),
        'SLUS_202.02',
      );

      expect(found, isNotNull);
      expect(found!.sector, 24);
      expect(found.size, 2048);
    });
  });

  group('a directory extent that is not one', () {
    test('does not run off the end of the sector', () async {
      // Every byte is 20, so each "record" declares a length under the 33-byte
      // fixed part. The walk strides to offset 2020, where 2020 + 20 still
      // passes the length check and buffer[2052] does not exist.
      final garbage = Uint8List(2048)..fillRange(0, 2048, 20);

      await expectLater(
        Iso9660.findFile(
          trackOf({
            16: volumeDescriptor(rootSector: 20, rootSize: 2048),
            20: garbage,
          }),
          'SLUS_202.02',
        ),
        completion(isNull),
      );
    });

    test('stops at a short record rather than reading its fixed part', () async {
      // The same thing one record in: a valid entry, then a length that cannot
      // describe a record. Everything after it is unreadable by definition, so
      // the walk ends there instead of trusting the byte.
      final root = directory({
        'SYSTEM.CNF;1': [22, 100],
      }).first;
      final firstLength = root[0];
      root[firstLength] = 8;

      await expectLater(
        Iso9660.findFile(
          trackOf({
            16: volumeDescriptor(rootSector: 20, rootSize: 2048),
            20: root,
          }),
          'SLUS_202.02',
        ),
        completion(isNull),
      );
    });

    test('a record of exactly the fixed length is still walked', () async {
      // 33 is a legal length — the boundary the guard must not swallow. The
      // entry it introduces has no name, so the walk steps over it and finds
      // what follows.
      final root = directory({
        'SLUS_202.02;1': [24, 2048],
      }).first;
      final firstLength = root[0];
      root[firstLength] = 33;
      final wanted = 'SYSTEM.CNF;1'.codeUnits;
      var offset = firstLength + 33;
      root[offset] = 33 + wanted.length + 1;
      root[offset + 2] = 22;
      root[offset + 10] = 100;
      root[offset + 32] = wanted.length;
      root.setRange(offset + 33, offset + 33 + wanted.length, wanted);

      final found = await Iso9660.findFile(
        trackOf({
          16: volumeDescriptor(rootSector: 20, rootSize: 2048),
          20: root,
        }),
        'SYSTEM.CNF',
      );

      expect(found, isNotNull, reason: '33 bytes is a legal record');
      expect(found!.sector, 22);
    });
  });
}
