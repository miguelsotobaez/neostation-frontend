import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../../services/logger_service.dart';
import 'disc_image.dart';
import 'iso9660.dart';

/// RetroAchievements' disc hashing, in the shapes rcheevos defines them.
///
/// A disc game is identified by what is *inside* the image — the boot
/// executable, or a console header — never by the container. That is why a
/// full-file MD5 of a `.chd` matches nothing in RA's database however correct
/// the MD5 is, and why every disc system in a library sits unmatched until this
/// runs.
///
/// Each method takes an already-opened track so the container, the filesystem
/// and the algorithm stay separable: the same code hashes a `.chd`, a `.cue`
/// and an `.iso`.
class RaDiscHasher {
  static final _log = LoggerService.instance;

  /// The most of a file RetroAchievements will hash. Matches rcheevos, and
  /// bounds what a corrupt directory record can make us read.
  static const int maxHashedBytes = 64 * 1024 * 1024;

  /// PlayStation: the boot executable named by `SYSTEM.CNF`, hashed together
  /// with its own filename.
  ///
  /// The filename is part of the hash because a handful of games share an
  /// engine and differ only in their data files — but never in their serial,
  /// which is what the boot file is named after.
  static Future<String?> hashPlaystation(DiscTrack track) async {
    var executable = await _findPlaystationExecutable(
      track,
      bootKey: 'BOOT',
      cdromPrefix: 'cdrom:',
    );

    if (executable == null) {
      final fallback = await Iso9660.findFile(track, 'PSX.EXE');
      if (fallback != null) {
        executable = _Executable('PSX.EXE', fallback.sector, fallback.size);
      }
    }

    if (executable == null) {
      _log.w('RA disc: could not locate primary executable');
      return null;
    }

    final header = await track.read(executable.sector);
    if (header == null) return null;

    var size = executable.size;
    if (_startsWith(header, 'PS-X EXE')) {
      // The PS-X EXE header states the executable's size 28 bytes in, not
      // counting the 2048-byte header itself, which the hash does include.
      size = _readUint32LE(header, 28) + 2048;
    } else {
      _log.i('RA disc: ${executable.name} has no PS-X EXE marker');
    }

    final digest = _DigestSink();
    final sink = crypto.md5.startChunkedConversion(digest);
    sink.add(executable.name.codeUnits);
    if (!await _addFile(sink, track, executable.sector, size)) return null;
    sink.close();
    return digest.value?.toString();
  }

  /// PlayStation 2: the same shape as [hashPlaystation], with the PS2 spelling
  /// of the boot key and no size stated inside the executable.
  static Future<String?> hashPlaystation2(DiscTrack track) async {
    final executable = await _findPlaystationExecutable(
      track,
      bootKey: 'BOOT2',
      cdromPrefix: 'cdrom0:',
    );
    if (executable == null) {
      _log.w('RA disc: could not locate primary executable');
      return null;
    }

    final digest = _DigestSink();
    final sink = crypto.md5.startChunkedConversion(digest);
    sink.add(executable.name.codeUnits);
    if (!await _addFile(sink, track, executable.sector, executable.size)) {
      return null;
    }
    sink.close();
    return digest.value?.toString();
  }

  /// PSP: `PSP_GAME/PARAM.SFO` followed by `PSP_GAME/SYSDIR/EBOOT.BIN`.
  ///
  /// The executable alone is not enough — some are a shared engine — so the
  /// metadata that names the game is hashed with it.
  static Future<String?> hashPsp(DiscTrack track) async {
    final params = await Iso9660.findFile(track, 'PSP_GAME\\PARAM.SFO');
    if (params == null) {
      _log.w('RA disc: not a PSP game disc');
      return null;
    }
    final boot = await Iso9660.findFile(track, 'PSP_GAME\\SYSDIR\\EBOOT.BIN');
    if (boot == null) {
      _log.w('RA disc: could not find primary executable');
      return null;
    }

    final digest = _DigestSink();
    final sink = crypto.md5.startChunkedConversion(digest);
    if (!await _addFile(sink, track, params.sector, params.size)) return null;
    if (!await _addFile(sink, track, boot.sector, boot.size)) return null;
    sink.close();
    return digest.value?.toString();
  }

  /// Sega CD and Saturn: the first 512 bytes of the disc.
  ///
  /// Those hold the volume and ROM headers, which identify the game. What
  /// follows them is region-check code and then an arbitrary number of
  /// executables, so there is no single "primary" one to hash.
  static Future<String?> hashSegaDisc(DiscTrack track) async {
    final sector = await track.read(track.info.startLba);
    if (sector == null) return null;

    if (!_startsWith(sector, 'SEGADISCSYSTEM  ') &&
        !_startsWith(sector, 'SEGA SEGASATURN ')) {
      _log.w('RA disc: not a Sega CD or Saturn disc');
      return null;
    }

    return crypto.md5.convert(sector.sublist(0, 512)).toString();
  }

  /// PC Engine CD: the boot header in sector 1 of the data track, then the
  /// program it points at.
  ///
  /// GameExpress discs have no such header and carry a normal filesystem
  /// instead, where the executable is `BOOT.BIN`.
  static Future<String?> hashPcEngineCd(DiscTrack track) async {
    final header = await track.read(track.info.startLba + 1);
    if (header == null) return null;

    if (_startsWith(header, 'PC Engine CD-ROM SYSTEM', offset: 32)) {
      final digest = _DigestSink();
      final sink = crypto.md5.startChunkedConversion(digest);
      // The last 22 bytes of the header are the disc's title.
      sink.add(header.sublist(106, 128));

      var sector =
          (header[0] << 16) +
          (header[1] << 8) +
          header[2] +
          track.info.startLba;
      var remaining = header[3];
      while (remaining > 0) {
        final data = await track.read(sector);
        if (data == null) return null;
        sink.add(data);
        sector++;
        remaining--;
      }
      sink.close();
      return digest.value?.toString();
    }

    final boot = await Iso9660.findFile(track, 'BOOT.BIN');
    if (boot == null || boot.size >= maxHashedBytes) {
      _log.w('RA disc: not a PC Engine CD');
      return null;
    }

    final digest = _DigestSink();
    final sink = crypto.md5.startChunkedConversion(digest);
    if (!await _addFile(sink, track, boot.sector, boot.size)) return null;
    sink.close();
    return digest.value?.toString();
  }

  /// Reads `BOOT`/`BOOT2` out of `SYSTEM.CNF` and locates what it names.
  static Future<_Executable?> _findPlaystationExecutable(
    DiscTrack track, {
    required String bootKey,
    required String cdromPrefix,
  }) async {
    final config = await Iso9660.findFile(track, 'SYSTEM.CNF');
    if (config == null) return null;

    final sector = await track.read(config.sector);
    if (sector == null) return null;

    final text = String.fromCharCodes(sector);
    for (final rawLine in text.split(RegExp(r'[\r\n]+'))) {
      final line = rawLine.trim();
      if (!line.startsWith(bootKey)) continue;

      final equals = line.indexOf('=', bootKey.length);
      if (equals < 0) continue;

      var value = line.substring(equals + 1).trim();
      if (value.startsWith(cdromPrefix)) {
        value = value.substring(cdromPrefix.length);
      }
      while (value.startsWith('\\')) {
        value = value.substring(1);
      }

      // The name ends at the version suffix or at whitespace, and the rest of
      // the sector is NUL padding.
      final end = value.indexOf(RegExp(r'[;\s\x00]'));
      final name = end < 0 ? value : value.substring(0, end);
      if (name.isEmpty) continue;

      final file = await Iso9660.findFile(track, name);
      if (file == null) return null;
      return _Executable(name, file.sector, file.size);
    }

    return null;
  }

  /// Feeds [size] bytes starting at [sector] into [sink], a sector at a time.
  static Future<bool> _addFile(
    ByteConversionSink sink,
    DiscTrack track,
    int sector,
    int size,
  ) async {
    var remaining = size > maxHashedBytes ? maxHashedBytes : size;
    var current = sector;

    while (remaining > 0) {
      final data = await track.read(current);
      if (data == null) return false;
      if (remaining >= data.length) {
        sink.add(data);
        remaining -= data.length;
      } else {
        sink.add(data.sublist(0, remaining));
        remaining = 0;
      }
      current++;
    }
    return true;
  }

  static bool _startsWith(Uint8List bytes, String marker, {int offset = 0}) {
    if (bytes.length < offset + marker.length) return false;
    for (var i = 0; i < marker.length; i++) {
      if (bytes[offset + i] != marker.codeUnitAt(i)) return false;
    }
    return true;
  }

  static int _readUint32LE(Uint8List bytes, int offset) {
    if (offset + 4 > bytes.length) return 0;
    return bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
  }
}

class _Executable {
  final String name;
  final int sector;
  final int size;

  const _Executable(this.name, this.sector, this.size);
}

/// Catches the digest a chunked MD5 conversion produces.
class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;

  @override
  void add(crypto.Digest data) => value = data;

  @override
  void close() {}
}
