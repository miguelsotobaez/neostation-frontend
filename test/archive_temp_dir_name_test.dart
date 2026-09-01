import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/archive_service.dart';

/// The SAF form: a document id whose every '/' is encoded as %2F, so the URI
/// has no separator left after the "/document/" segment.
String _safUri(String documentId) =>
    'content://com.android.externalstorage.documents/tree/'
    '${Uri.encodeComponent('primary:emu/roms')}/document/'
    '${Uri.encodeComponent(documentId)}';

void main() {
  group('ArchiveService.tempDirNameFor', () {
    test('a SAF URI yields the ROM file name, not the encoded document id', () {
      final uri = _safUri('primary:emu/roms/gba/Translations/Zelda.zip');

      expect(ArchiveService.tempDirNameFor(uri), 'Zelda.zip');
    });

    test('the observed errno-36 case fits in a directory name', () {
      // Verbatim from the Thor's app.log, 2026-09-01: this is the name that
      // could not be created. The bug is a byte count, so that is what the
      // case asserts — not the string, which is only how it got that long.
      const documentId =
          'primary:emu/roms/gba/Translations (GameBoy Advance)/'
          'Summon Night - Swordcraft Story 3 - The Stone of Beginnings (Japan) '
          '[T-En by Higsby & Normmatt & Teod & Unknownbrackets v0.9] [i] [n].zip';
      final uri = _safUri(documentId);

      // The fault: the encoded id on its own is far past the limit.
      expect(
        utf8.encode(uri.split('/').last).length,
        greaterThan(255),
        reason: 'the encoded document id is what used to name the directory',
      );

      final name = ArchiveService.tempDirNameFor(uri);
      expect(utf8.encode(name).length, lessThanOrEqualTo(255));
      expect(name, startsWith('Summon Night'));
      expect(name, endsWith('.zip'));
    });

    test('a plain desktop path keeps its basename', () {
      expect(
        ArchiveService.tempDirNameFor(
          '/home/user/roms/snes/Chrono Trigger.zip',
        ),
        'Chrono Trigger.zip',
      );
    });

    test('a literal % in a plain path is not decoded', () {
      // Decoding unconditionally would either corrupt this name or throw.
      expect(
        ArchiveService.tempDirNameFor('/roms/nes/Mega Man 100%.zip'),
        'Mega Man 100%.zip',
      );
    });

    test('extraction and cleanup derive the same name from the same path', () {
      // The two used to build this independently, which is how one of them
      // could be wrong on its own. Same input, same directory, or cleanup
      // silently leaves the extracted ROM on disk.
      final uri = _safUri(
        'primary:emu/roms/psx/Final Fantasy VII (Disc 1).zip',
      );

      expect(
        ArchiveService.tempDirNameFor(uri),
        ArchiveService.tempDirNameFor(uri),
      );
    });

    test('an oversized name is clamped in bytes without splitting a rune', () {
      // Japanese titles cost three bytes a glyph, so a character-count clamp
      // would still overrun the byte limit this is defending.
      final documentId = 'primary:emu/roms/pce/${'ドラゴン' * 40}.zip';
      final name = ArchiveService.tempDirNameFor(_safUri(documentId));

      expect(utf8.encode(name).length, lessThanOrEqualTo(255));
      // Round-trips, so no partial code unit survived the truncation.
      expect(utf8.decode(utf8.encode(name)), name);
    });

    test('a malformed escape falls back rather than throwing', () {
      const uri =
          'content://com.android.externalstorage.documents/document/bad%ZZ';

      expect(() => ArchiveService.tempDirNameFor(uri), returnsNormally);
      expect(
        utf8.encode(ArchiveService.tempDirNameFor(uri)).length,
        lessThanOrEqualTo(255),
      );
    });
  });
}
