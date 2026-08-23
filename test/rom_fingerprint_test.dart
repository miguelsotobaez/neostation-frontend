import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/rom_fingerprint_service.dart';
import 'package:neostation/utils/optimized_md5_utils.dart';

/// Tests for the ScreenScraper dump identity: the crc32/md5/size of the ROM
/// image itself.
void main() {
  late Directory tempDir;

  /// Deterministic, poorly-compressible-ish bytes so a zip is a real zip.
  Uint8List payload(int length, {int seed = 0}) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = (i * 31 + (i >> 7) + seed) & 0xff;
    }
    return bytes;
  }

  String hex32(int crc) => crc.toRadixString(16).toUpperCase().padLeft(8, '0');

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('rom_fingerprint_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  group('bare ROM file', () {
    test('produces the crc32, md5 and size of the file', () async {
      final bytes = payload(64 * 1024);
      final romPath = '${tempDir.path}/Game.nes';
      await File(romPath).writeAsBytes(bytes);

      final result = await RomFingerprintService.fingerprint(romPath, 'nes');

      expect(result.skipReason, isNull);
      expect(result.fingerprint!.crc32, hex32(getCrc32(bytes)));
      expect(result.fingerprint!.md5, crypto.md5.convert(bytes).toString());
      expect(result.fingerprint!.sizeBytes, bytes.length);
    });

    test('crc32 is uppercase and zero-padded to 8 chars', () async {
      // Chosen so the checksum has leading zeroes to pad.
      final romPath = '${tempDir.path}/Tiny.nes';
      await File(romPath).writeAsBytes(payload(3));

      final result = await RomFingerprintService.fingerprint(romPath, 'nes');

      expect(result.fingerprint!.crc32.length, 8);
      expect(
        result.fingerprint!.crc32,
        result.fingerprint!.crc32.toUpperCase(),
      );
    });
  });

  group('zipped ROM', () {
    test('reports the inner ROM, not the archive', () async {
      final inner = payload(128 * 1024);
      final archive = Archive()..add(ArchiveFile.bytes('Game.nes', inner));
      final zipPath = '${tempDir.path}/Game.zip';
      final zipBytes = ZipEncoder().encode(archive);
      await File(zipPath).writeAsBytes(zipBytes);

      final result = await RomFingerprintService.fingerprint(zipPath, 'nes');

      expect(result.skipReason, isNull);
      // The value ScreenScraper indexes is the inner image's checksum.
      expect(result.fingerprint!.crc32, hex32(getCrc32(inner)));
      expect(result.fingerprint!.sizeBytes, inner.length);
      // And explicitly NOT the container's.
      expect(result.fingerprint!.crc32, isNot(hex32(getCrc32(zipBytes))));
    });

    test('takes the cheap path, leaving md5 unset', () async {
      final archive = Archive()
        ..add(ArchiveFile.bytes('Game.nes', payload(32 * 1024)));
      final zipPath = '${tempDir.path}/Cheap.zip';
      await File(zipPath).writeAsBytes(ZipEncoder().encode(archive));

      final result = await RomFingerprintService.fingerprint(zipPath, 'nes');

      // crc alone resolves a ScreenScraper lookup, so nothing was decompressed
      // and there is no md5 to report.
      expect(result.fingerprint!.crc32, isNotEmpty);
      expect(result.fingerprint!.md5, isNull);
    });

    test('picks the largest entry, as extraction does', () async {
      final rom = payload(64 * 1024, seed: 7);
      final archive = Archive()
        ..add(ArchiveFile.bytes('readme.txt', payload(64)))
        ..add(ArchiveFile.bytes('Game.nes', rom));
      final zipPath = '${tempDir.path}/WithReadme.zip';
      await File(zipPath).writeAsBytes(ZipEncoder().encode(archive));

      final result = await RomFingerprintService.fingerprint(zipPath, 'nes');

      expect(result.fingerprint!.crc32, hex32(getCrc32(rom)));
    });

    test('an arcade set is identified by the archive itself', () async {
      final archive = Archive()
        ..add(ArchiveFile.bytes('rom1.bin', payload(4096)))
        ..add(ArchiveFile.bytes('rom2.bin', payload(4096, seed: 3)));
      final zipPath = '${tempDir.path}/sf2.zip';
      final zipBytes = ZipEncoder().encode(archive);
      await File(zipPath).writeAsBytes(zipBytes);

      // In the app this flag comes from the system's declared hash policy
      // (assets/systems/<sys>.json, #375); the fingerprinter itself never
      // reads the database.
      final result = await RomFingerprintService.fingerprint(
        zipPath,
        'cps2',
        keepsArchivesPacked: true,
      );

      // An arcade set IS its zip; the inner files are not separate ROMs.
      expect(result.fingerprint!.crc32, hex32(getCrc32(zipBytes)));
      expect(result.fingerprint!.sizeBytes, zipBytes.length);
    });
  });

  group('cheap-first effort', () {
    test('a zipped ROM is fingerprinted without reading it', () async {
      final inner = payload(64 * 1024);
      final archive = Archive()..add(ArchiveFile.bytes('Game.nes', inner));
      final zipPath = '${tempDir.path}/Cheap.zip';
      await File(zipPath).writeAsBytes(ZipEncoder().encode(archive));

      final result = await RomFingerprintService.fingerprint(
        zipPath,
        'nes',
        effort: FingerprintEffort.cheapOnly,
      );

      expect(result.fingerprint!.crc32, hex32(getCrc32(inner)));
      expect(result.skipReason, isNull);
    });

    test('a bare ROM defers instead of reading the whole file', () async {
      final romPath = '${tempDir.path}/Bare.nes';
      await File(romPath).writeAsBytes(payload(64 * 1024));

      final result = await RomFingerprintService.fingerprint(
        romPath,
        'nes',
        effort: FingerprintEffort.cheapOnly,
      );

      expect(result.fingerprint, isNull);
      expect(result.skipReason, RomFingerprintService.deferredCostly);
    });

    test('deferring is distinct from every real failure reason', () {
      // The caller keys off this to decide whether to park the ROM; if it ever
      // collided with a skip reason, a deferred ROM would be parked and the
      // full pass would never see it.
      expect(
        RomFingerprintService.deferredCostly,
        isNot(RomFingerprintService.skipMissing),
      );
      expect(
        RomFingerprintService.deferredCostly,
        isNot(RomFingerprintService.skipOversize),
      );
      expect(
        RomFingerprintService.deferredCostly,
        isNot(RomFingerprintService.skipDisc),
      );
      expect(
        RomFingerprintService.deferredCostly,
        isNot(RomFingerprintService.skipExtractFailed),
      );
      expect(
        RomFingerprintService.deferredCostly,
        isNot(RomFingerprintService.skipError),
      );
      // And it can never be treated as a permanent park either.
      expect(
        RomFingerprintService.permanentSkipReasons,
        isNot(contains(RomFingerprintService.deferredCostly)),
      );
    });

    test('permanent skip reasons are the deterministic subset', () {
      // These suppress any re-attempt on later scrapes, so a transient reason
      // landing in here would park a ROM forever with no UI to clear it.
      // missing (an unmounted card) and error (an I/O hiccup) must stay
      // retryable; the deterministic three cannot fix themselves.
      expect(RomFingerprintService.permanentSkipReasons, {
        RomFingerprintService.skipOversize,
        RomFingerprintService.skipDisc,
        RomFingerprintService.skipExtractFailed,
      });
      expect(
        RomFingerprintService.permanentSkipReasons,
        isNot(contains(RomFingerprintService.skipMissing)),
      );
      expect(
        RomFingerprintService.permanentSkipReasons,
        isNot(contains(RomFingerprintService.skipError)),
      );
    });

    test('a disc image is still parked, not deferred', () async {
      final romPath = '${tempDir.path}/Game.chd';
      await File(romPath).writeAsBytes(payload(1024));

      final result = await RomFingerprintService.fingerprint(
        romPath,
        'ps1',
        effort: FingerprintEffort.cheapOnly,
      );

      expect(result.skipReason, RomFingerprintService.skipDisc);
    });

    test('the full pass reads what the cheap pass deferred', () async {
      final bytes = payload(64 * 1024);
      final romPath = '${tempDir.path}/Bare2.nes';
      await File(romPath).writeAsBytes(bytes);

      final result = await RomFingerprintService.fingerprint(
        romPath,
        'nes',
        effort: FingerprintEffort.full,
      );

      expect(result.fingerprint!.crc32, hex32(getCrc32(bytes)));
      expect(result.fingerprint!.md5, crypto.md5.convert(bytes).toString());
    });
  });

  group('zip central directory parsing', () {
    // The parser is hand-rolled rather than going through ZipDecoder, so it has
    // to be shown to agree with the bytes it claims to describe.
    test('agrees with the crc of the actual decompressed content', () async {
      for (final size in [1, 1024, 100 * 1024]) {
        final inner = payload(size, seed: size);
        final archive = Archive()..add(ArchiveFile.bytes('r.bin', inner));
        final zipPath = '${tempDir.path}/agree_$size.zip';
        await File(zipPath).writeAsBytes(ZipEncoder().encode(archive));

        final result = await RomFingerprintService.fingerprint(zipPath, 'nes');

        expect(
          result.fingerprint!.crc32,
          hex32(getCrc32(inner)),
          reason: 'crc mismatch at $size bytes',
        );
        expect(
          result.fingerprint!.sizeBytes,
          inner.length,
          reason: 'size mismatch at $size bytes',
        );
      }
    });

    test('survives an archive comment sitting after the record', () async {
      // The comment is scanned past to find the record; a naive parser that
      // assumed the record was the last 22 bytes would miss it.
      final inner = payload(4096);
      final archive = Archive()..add(ArchiveFile.bytes('r.bin', inner));
      final zipped = ZipEncoder().encode(archive);

      final comment = List<int>.filled(300, 0x41);
      final withComment = Uint8List.fromList([...zipped, ...comment]);
      // Patch the comment length in the record so the archive stays valid.
      withComment[zipped.length - 2] = comment.length & 0xff;
      withComment[zipped.length - 1] = (comment.length >> 8) & 0xff;

      final zipPath = '${tempDir.path}/commented.zip';
      await File(zipPath).writeAsBytes(withComment);

      final result = await RomFingerprintService.fingerprint(zipPath, 'nes');

      expect(result.fingerprint!.crc32, hex32(getCrc32(inner)));
    });

    test(
      'falls back to extraction when the archive is not a zip at all',
      () async {
        final zipPath = '${tempDir.path}/Corrupt.zip';
        await File(zipPath).writeAsBytes(payload(2048));

        // No readable directory, so the cheap path declines and the full path
        // tries to extract — which also fails, and that is a real skip.
        final result = await RomFingerprintService.fingerprint(zipPath, 'nes');

        expect(result.fingerprint, isNull);
        expect(result.skipReason, isNotNull);
        expect(result.skipReason, isNot(RomFingerprintService.deferredCostly));
      },
    );
  });

  group('chunked reading', () {
    test('resumes crc32 and md5 correctly across chunk boundaries', () async {
      final bytes = payload(300 * 1024);
      final romPath = '${tempDir.path}/Chunked.bin';
      await File(romPath).writeAsBytes(bytes);

      int crc = 0;
      int size = 0;
      final collected = BytesBuilder();
      await OptimizedMd5Utils.readChunked(romPath, (chunk) {
        crc = getCrc32(chunk, crc);
        size += chunk.length;
        collected.add(chunk);
      }, chunkSize: 4096);

      expect(size, bytes.length);
      expect(crc, getCrc32(bytes));
      expect(collected.toBytes(), bytes);
    });
  });

  group('ROMs that cannot be fingerprinted', () {
    test('parks a missing file', () async {
      final result = await RomFingerprintService.fingerprint(
        '${tempDir.path}/does-not-exist.nes',
        'nes',
      );

      expect(result.fingerprint, isNull);
      expect(result.skipReason, RomFingerprintService.skipMissing);
    });

    test('parks a disc image', () async {
      final romPath = '${tempDir.path}/Game.chd';
      await File(romPath).writeAsBytes(payload(1024));

      final result = await RomFingerprintService.fingerprint(romPath, 'ps1');

      expect(result.fingerprint, isNull);
      expect(result.skipReason, RomFingerprintService.skipDisc);
    });
  });
}
