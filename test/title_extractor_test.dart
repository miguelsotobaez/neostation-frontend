import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/switch_title_extractor.dart';
import 'package:neostation/utils/vita_title_extractor.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('extractor_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('VitaTitleExtractor', () {
    test('extracts trimmed title ID from standard file', () async {
      final file = File('${tempDir.path}/game.psvita');
      await file.writeAsString('  PCSB00001  \n');

      final titleId = await VitaTitleExtractor.extractTitleId(file.path);
      expect(titleId, equals('PCSB00001'));
    });

    test('returns null for empty file', () async {
      final file = File('${tempDir.path}/empty.psvita');
      await file.writeAsString('   ');

      final titleId = await VitaTitleExtractor.extractTitleId(file.path);
      expect(titleId, isNull);
    });

    test('returns null for non-existent file', () async {
      final titleId = await VitaTitleExtractor.extractTitleId(
        '${tempDir.path}/nonexistent.psvita',
      );
      expect(titleId, isNull);
    });
  });

  group('SwitchTitleExtractor', () {
    test('loadKeys initializes production encryption keys', () async {
      final success = await SwitchTitleExtractor.loadKeys();
      expect(success, isTrue);
    });

    test('returns null gracefully for non-existent file', () async {
      final info = await SwitchTitleExtractor.extractGameInfo(
        '${tempDir.path}/nonexistent.nsp',
      );
      expect(info, isNull);
    });

    test('returns null gracefully for unsupported extension', () async {
      final file = File('${tempDir.path}/game.zip');
      await file.writeAsBytes([0x00, 0x01]);

      final info = await SwitchTitleExtractor.extractGameInfo(file.path);
      expect(info, isNull);
    });

    test(
      'returns null gracefully for corrupt/invalid container file',
      () async {
        final file = File('${tempDir.path}/corrupt.nsp');
        await file.writeAsBytes([0x00, 0x01, 0x02, 0x03, 0x04]);

        final info = await SwitchTitleExtractor.extractGameInfo(file.path);
        expect(info, isNull);
      },
    );
  });
}
