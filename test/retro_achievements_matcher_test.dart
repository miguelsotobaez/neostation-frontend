import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/retro_achievements_matcher.dart';

void main() {
  group('RetroAchievementsMatcher.sanitizeRomName', () {
    test('strips the file extension', () {
      expect(
        RetroAchievementsMatcher.sanitizeRomName('Chrono Trigger.sfc'),
        'Chrono Trigger',
      );
    });

    test('strips (parenthesised) region/revision tags', () {
      expect(
        RetroAchievementsMatcher.sanitizeRomName('Super Mario World (USA).sfc'),
        'Super Mario World',
      );
    });

    test('strips [bracketed] dump flags', () {
      expect(RetroAchievementsMatcher.sanitizeRomName('Sonic [!].md'), 'Sonic');
    });

    test('strips multiple tags and trims residual whitespace', () {
      expect(
        RetroAchievementsMatcher.sanitizeRomName(
          'Final Fantasy VI (Japan) [T-En].sfc',
        ),
        'Final Fantasy VI',
      );
    });

    test(
      'keeps dots that belong to the title (only the last is extension)',
      () {
        expect(
          RetroAchievementsMatcher.sanitizeRomName('Mega Man X.v1.1.smc'),
          'Mega Man X.v1.1',
        );
      },
    );

    test('handles a name with no extension', () {
      expect(RetroAchievementsMatcher.sanitizeRomName('Contra'), 'Contra');
    });
  });

  group('RetroAchievementsMatcher.normalizeTitle', () {
    test('lowercases, strips punctuation and collapses whitespace', () {
      expect(
        RetroAchievementsMatcher.normalizeTitle("Marvel's Spider-Man"),
        'marvels spiderman',
      );
    });

    test('collapses runs of internal whitespace to single spaces', () {
      expect(
        RetroAchievementsMatcher.normalizeTitle('Street   Fighter  II'),
        'street fighter ii',
      );
    });

    test('two titles differing only in punctuation normalize equal', () {
      expect(
        RetroAchievementsMatcher.normalizeTitle('Legend of Zelda: A Link'),
        RetroAchievementsMatcher.normalizeTitle('Legend of Zelda - A Link'),
      );
    });

    test('trims leading and trailing whitespace', () {
      expect(RetroAchievementsMatcher.normalizeTitle('  Metroid  '), 'metroid');
    });
  });
}
