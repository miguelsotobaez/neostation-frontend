import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/providers/romm_provider.dart';
import 'package:path/path.dart' as p;

/// Writes [files] (name → bytes) into a zip at [zipPath].
void _writeZip(String zipPath, Map<String, List<int>> files) {
  final archive = Archive();
  files.forEach((name, bytes) {
    archive.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  final encoded = ZipEncoder().encode(archive);
  File(zipPath).writeAsBytesSync(encoded);
}

void main() {
  group('RommProvider.extractMultiDiscZip', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('romm_extract_test');
    });

    tearDown(() async {
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    test(
      'bundled m3u: discs sit alongside m3u, playlist rewritten, zip removed',
      () async {
        final zipPath = p.join(dir.path, 'Alone in the Dark.zip');
        _writeZip(zipPath, {
          'Alone in the Dark (Disc 1).chd': [1, 2, 3],
          'Alone in the Dark (Disc 2).chd': [4, 5, 6],
          'Alone in the Dark.m3u':
              'Alone in the Dark (Disc 1).chd\nAlone in the Dark (Disc 2).chd\n'
                  .codeUnits,
        });

        final m3uName = await RommProvider.extractMultiDiscZip(
          zipPath,
          dir.path,
          'Alone in the Dark',
        );

        expect(m3uName, 'Alone in the Dark.m3u');
        // Zip is consumed.
        expect(File(zipPath).existsSync(), isFalse);
        // Discs extracted alongside the m3u in the ROM folder root.
        expect(
          File(p.join(dir.path, 'Alone in the Dark (Disc 1).chd')).existsSync(),
          isTrue,
        );
        expect(
          File(p.join(dir.path, 'Alone in the Dark (Disc 2).chd')).existsSync(),
          isTrue,
        );
        // No .hidden subfolder is created.
        expect(Directory(p.join(dir.path, '.hidden')).existsSync(), isFalse);
        // Playlist sits in root and references discs by bare basename, in the
        // bundled order.
        final playlist = File(
          p.join(dir.path, 'Alone in the Dark.m3u'),
        ).readAsLinesSync();
        expect(playlist, [
          'Alone in the Dark (Disc 1).chd',
          'Alone in the Dark (Disc 2).chd',
        ]);
      },
    );

    test('preserves bundled playlist order over filename order', () async {
      final zipPath = p.join(dir.path, 'g.zip');
      // Disc 2 listed first in the playlist — order must be honoured.
      _writeZip(zipPath, {
        'g (Disc 1).chd': [1],
        'g (Disc 2).chd': [2],
        'g.m3u': 'g (Disc 2).chd\ng (Disc 1).chd\n'.codeUnits,
      });

      await RommProvider.extractMultiDiscZip(zipPath, dir.path, 'g');

      final playlist = File(p.join(dir.path, 'g.m3u')).readAsLinesSync();
      expect(playlist, ['g (Disc 2).chd', 'g (Disc 1).chd']);
    });

    test(
      'synthesises a playlist in name order when the zip has no m3u',
      () async {
        final zipPath = p.join(dir.path, 'nogm3u.zip');
        _writeZip(zipPath, {
          'Game (Disc 2).chd': [2],
          'Game (Disc 1).chd': [1],
        });

        final m3uName = await RommProvider.extractMultiDiscZip(
          zipPath,
          dir.path,
          'Game',
        );

        expect(m3uName, 'Game.m3u');
        final playlist = File(p.join(dir.path, 'Game.m3u')).readAsLinesSync();
        expect(playlist, ['Game (Disc 1).chd', 'Game (Disc 2).chd']);
      },
    );

    test('returns null and leaves the zip when it holds only an m3u', () async {
      final zipPath = p.join(dir.path, 'empty.zip');
      _writeZip(zipPath, {'only.m3u': 'nothing.chd\n'.codeUnits});

      final m3uName = await RommProvider.extractMultiDiscZip(
        zipPath,
        dir.path,
        'only',
      );

      expect(m3uName, isNull);
      expect(File(zipPath).existsSync(), isTrue);
    });
  });
}
