import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:neostation/services/storage_space_service.dart';

/// Covers the free-space probe behind the RomM bulk sync's pre-flight check.
///
/// The rule the whole class exists to keep is that it fails *open*: anything it
/// can't measure answers null, which the caller reads as "no opinion" and lets
/// the download proceed. A wrong zero would warn about a full disk that isn't.
void main() {
  group('parseDfOutput', () {
    test('reads the available column of a df -Pk row', () {
      expect(
        StorageSpaceService.parseDfOutput(
          '/dev/sda1 480588496 120147124 336014820 27% /',
        ),
        336014820 * 1024,
      );
    });

    test('tolerates the wider spacing df pads columns with', () {
      expect(
        StorageSpaceService.parseDfOutput(
          '/dev/block/dm-5    59736064   38271488    21464576  65% /storage/emulated',
        ),
        21464576 * 1024,
      );
    });

    test('a header, a truncated row or junk parses to nothing', () {
      expect(
        StorageSpaceService.parseDfOutput(
          'Filesystem 1024-blocks Used Available Capacity Mounted on',
        ),
        isNull,
      );
      expect(StorageSpaceService.parseDfOutput('/dev/sda1 480588496'), isNull);
      expect(StorageSpaceService.parseDfOutput(''), isNull);
    });
  });

  group('parseDfMountPoint', () {
    test('reads the mounted-on column of a df -Pk row', () {
      expect(
        StorageSpaceService.parseDfMountPoint(
          '/dev/sda1 480588496 120147124 336014820 27% /',
        ),
        '/',
      );
      expect(
        StorageSpaceService.parseDfMountPoint(
          '/dev/block/dm-5    59736064   38271488    21464576  65% /storage/emulated',
        ),
        '/storage/emulated',
      );
    });

    test('keeps a mount point that contains spaces', () {
      // The removable-media case on desktop Linux: only the last column can
      // contain a space, so it cannot be read by splitting on whitespace.
      expect(
        StorageSpaceService.parseDfMountPoint(
          '/dev/sdb1 1000 500 500 50% /run/media/deck/My SD Card',
        ),
        '/run/media/deck/My SD Card',
      );
    });

    test('a truncated row or junk parses to nothing', () {
      expect(
        StorageSpaceService.parseDfMountPoint('/dev/sda1 480588496 1 1 5%'),
        isNull,
      );
      expect(StorageSpaceService.parseDfMountPoint(''), isNull);
    });
  });

  group('androidVolumeRoot', () {
    test('primary shared storage is the volume, not the folder on it', () {
      expect(
        StorageSpaceService.androidVolumeRoot(
          '/storage/emulated/0/Emulation/roms/snes',
        ),
        '/storage/emulated/0',
      );
      // A second Android user is a different volume root.
      expect(
        StorageSpaceService.androidVolumeRoot('/storage/emulated/10/roms'),
        '/storage/emulated/10',
      );
    });

    test('a removable volume is identified by its UUID', () {
      expect(
        StorageSpaceService.androidVolumeRoot('/storage/1A2B-3C4D/roms/psx'),
        '/storage/1A2B-3C4D',
      );
    });

    test('an SD card and internal storage are never the same volume', () {
      // The bug this whole mechanism exists for: two ROM folders whose free
      // space has nothing to do with each other.
      expect(
        StorageSpaceService.androidVolumeRoot('/storage/emulated/0/roms'),
        isNot(StorageSpaceService.androidVolumeRoot('/storage/1A2B-3C4D/roms')),
      );
    });

    test('the /sdcard symlink is primary storage under another name', () {
      expect(
        StorageSpaceService.androidVolumeRoot('/sdcard/roms/nes'),
        '/storage/emulated/0',
      );
      expect(
        StorageSpaceService.androidVolumeRoot('/sdcard'),
        '/storage/emulated/0',
      );
    });

    test('a path of no known shape stands alone', () {
      // Unknown shape means "assume nothing": the path is its own volume, so it
      // is checked on its own rather than pooled with something unrelated.
      expect(
        StorageSpaceService.androidVolumeRoot('/data/user/0/app/files'),
        '/data/user/0/app/files',
      );
      expect(StorageSpaceService.androidVolumeRoot('/storage'), '/storage');
    });
  });

  group('volumeFor', () {
    test('an empty path has no answer', () async {
      expect(await StorageSpaceService.volumeFor(''), isNull);
    });

    test('identifies and measures the volume in one pass', () async {
      final temp = await Directory.systemTemp.createTemp('romm_volume_test');
      addTearDown(() async {
        if (temp.existsSync()) await temp.delete(recursive: true);
      });

      final volume = await StorageSpaceService.volumeFor(temp.path);
      final child = await StorageSpaceService.volumeFor(
        p.join(temp.path, 'psx', 'not', 'created', 'yet'),
      );

      expect(volume, isNotNull);
      expect(volume!.id, isNotEmpty);
      expect(volume.freeBytes, isNotNull);
      expect(
        child!.id,
        volume.id,
        reason: 'a folder and its unborn subfolder are one volume',
      );
    }, skip: !(Platform.isLinux || Platform.isMacOS));
  });

  group('freeSpaceBytes', () {
    test('an empty path has no answer', () async {
      expect(await StorageSpaceService.freeSpaceBytes(''), isNull);
    });

    test(
      'measures the volume of a folder that does not exist yet',
      () async {
        // A sync's destination is often created on the way in, so the probe
        // has to answer for a path before anything has been written to it —
        // by walking up to the nearest existing ancestor, which is the same
        // volume.
        final temp = await Directory.systemTemp.createTemp('romm_space_test');
        addTearDown(() async {
          if (temp.existsSync()) await temp.delete(recursive: true);
        });

        final onDisk = await StorageSpaceService.freeSpaceBytes(temp.path);
        final notYet = await StorageSpaceService.freeSpaceBytes(
          p.join(temp.path, 'psx', 'not', 'created', 'yet'),
        );

        expect(onDisk, isNotNull);
        expect(onDisk, greaterThan(0));
        expect(notYet, isNotNull);
        // Same volume, so the same order of magnitude — not the same number,
        // since a live filesystem moves between the two calls.
        expect(
          (notYet! - onDisk!).abs(),
          lessThan(onDisk ~/ 10 + 1024 * 1024),
          reason: 'both readings describe the same mount',
        );
      },
      // `df` is the desktop backend; Android answers over its MethodChannel,
      // which has no binding in a plain unit test.
      skip: !(Platform.isLinux || Platform.isMacOS),
    );
  });
}
