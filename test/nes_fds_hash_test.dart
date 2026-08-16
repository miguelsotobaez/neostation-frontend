import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/optimized_md5_utils.dart';

/// RetroAchievements hashes NES and Famicom Disk System ROMs over the ROM data
/// only, excluding the 16-byte iNES ("NES\x1a") or FDS ("FDS\x1a") header when
/// one is present. A headered `.fds` hashed whole matches nothing in RA's
/// database, which is why FDS libraries came up almost entirely unmatched.
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nes_fds_hash_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  /// Disk/ROM payload that stays identical across the headered and headerless
  /// cases, so the tests compare like with like.
  final payload = List<int>.generate(4096, (i) => i % 256);
  String md5Of(List<int> bytes) => crypto.md5.convert(bytes).toString();

  Future<String> writeAndHash(String name, List<int> bytes) async {
    final file = File('${tempDir.path}/$name');
    await file.writeAsBytes(bytes);
    return OptimizedMd5Utils.calculateNesMd5(file.path);
  }

  test('skips the 16-byte FDS header', () async {
    final header = <int>[0x46, 0x44, 0x53, 0x1A, ...List.filled(12, 0)];

    expect(
      await writeAndHash('game.fds', [...header, ...payload]),
      md5Of(payload),
    );
  });

  test('skips the 16-byte iNES header', () async {
    final header = <int>[0x4E, 0x45, 0x53, 0x1A, ...List.filled(12, 0)];

    expect(
      await writeAndHash('game.nes', [...header, ...payload]),
      md5Of(payload),
    );
  });

  test('hashes a headerless disk image whole', () async {
    // Raw FDS disk images start with 0x01 0x2A 'N' 'I' and carry no header,
    // so the whole file is the hash input.
    final raw = <int>[0x01, 0x2A, 0x4E, 0x49, ...payload];

    expect(await writeAndHash('raw.fds', raw), md5Of(raw));
  });

  test('does not strip a header from a lookalike magic', () async {
    // Same three letters, no 0x1A terminator: not a header.
    final notHeader = <int>[0x46, 0x44, 0x53, 0x20, ...payload];

    expect(await writeAndHash('lookalike.fds', notHeader), md5Of(notHeader));
  });
}
