import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/utils/letter_jump.dart';

/// Builds a `letterAt` accessor over a compact "AABBC" style layout, where each
/// character is one item's alphabetical group.
String Function(int) lettersOf(String layout) =>
    (index) => layout[index];

void main() {
  group('LetterJump.letterForName', () {
    test('upper cases the first character', () {
      expect(LetterJump.letterForName('sonic the hedgehog'), 'S');
    });

    test('ignores a leading English article', () {
      expect(LetterJump.letterForName('The Legend of Zelda'), 'L');
    });

    test('keeps digits as their own group', () {
      expect(LetterJump.letterForName('1942'), '1');
    });

    test('collapses symbols and empty names into #', () {
      expect(LetterJump.letterForName('[BIOS] Something'), LetterJump.other);
      expect(LetterJump.letterForName('   '), LetterJump.other);
    });
  });

  group('LetterJump.targetIndex', () {
    test('forward lands on the first item of the next group', () {
      expect(
        LetterJump.targetIndex(
          length: 5,
          currentIndex: 0,
          forward: true,
          letterAt: lettersOf('AABBC'),
        ),
        2,
      );
    });

    test('forward from mid-group still lands on the next group', () {
      expect(
        LetterJump.targetIndex(
          length: 5,
          currentIndex: 1,
          forward: true,
          letterAt: lettersOf('AABBC'),
        ),
        2,
      );
    });

    test('forward returns null in the last group', () {
      expect(
        LetterJump.targetIndex(
          length: 5,
          currentIndex: 4,
          forward: true,
          letterAt: lettersOf('AABBC'),
        ),
        isNull,
      );
    });

    test('backward rewinds to the start of the current group first', () {
      expect(
        LetterJump.targetIndex(
          length: 5,
          currentIndex: 3,
          forward: false,
          letterAt: lettersOf('AABBC'),
        ),
        2,
      );
    });

    test('backward from a group start steps into the previous group', () {
      expect(
        LetterJump.targetIndex(
          length: 5,
          currentIndex: 2,
          forward: false,
          letterAt: lettersOf('AABBC'),
        ),
        0,
      );
    });

    test('backward returns null at the very first item', () {
      expect(
        LetterJump.targetIndex(
          length: 5,
          currentIndex: 0,
          forward: false,
          letterAt: lettersOf('AABBC'),
        ),
        isNull,
      );
    });

    test('treats a favourites block as its own group', () {
      // '*' = favourites pinned above the alphabetical run.
      const layout = '**ABB';
      expect(
        LetterJump.targetIndex(
          length: 5,
          currentIndex: 1,
          forward: true,
          letterAt: lettersOf(layout),
        ),
        2,
      );
      expect(
        LetterJump.targetIndex(
          length: 5,
          currentIndex: 2,
          forward: false,
          letterAt: lettersOf(layout),
        ),
        0,
      );
    });

    test('handles an empty or out-of-range list', () {
      expect(
        LetterJump.targetIndex(
          length: 0,
          currentIndex: 0,
          forward: true,
          letterAt: (_) => 'A',
        ),
        isNull,
      );
      expect(
        LetterJump.targetIndex(
          length: 3,
          currentIndex: 7,
          forward: true,
          letterAt: (_) => 'A',
        ),
        isNull,
      );
    });
  });
}
