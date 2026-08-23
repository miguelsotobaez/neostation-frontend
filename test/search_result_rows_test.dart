import 'package:flutter_test/flutter_test.dart';

import 'package:neostation/models/database_game_model.dart';
import 'package:neostation/models/romm_rom.dart';
import 'package:neostation/screens/search_screen/search_filter.dart';

/// Builds a minimal local result; only the identity matters to the row model.
DatabaseGameModel game(String filename) =>
    DatabaseGameModel(filename: filename, romPath: '/roms/$filename');

/// Builds a minimal RomM result; only the identity matters to the row model.
RommRom rom(int id, String name) => RommRom(
  id: id,
  name: name,
  platformId: 1,
  platformSlug: 'snes',
  fsName: '$name.zip',
  fsNameNoExt: name,
  fsExtension: 'zip',
);

void main() {
  group('buildResultRows local-only', () {
    test('every local result is focusable, in order', () {
      final built = buildResultRows(
        results: [game('a.sfc'), game('b.sfc'), game('c.sfc')],
      );

      expect(built.rows, hasLength(3));
      expect(built.rows.every((r) => r is LocalRow), isTrue);
      expect(built.focusable, [
        0,
        1,
        2,
      ], reason: 'with no RomM section the two index spaces coincide');
    });

    test('an empty library produces no rows and nothing focusable', () {
      final built = buildResultRows(results: []);

      expect(built.rows, isEmpty);
      expect(built.focusable, isEmpty);
      expect(built.rowAtSelection(0), isNull);
    });
  });

  group('buildResultRows with a RomM section', () {
    ResultRows withRemote({bool hasMore = false, bool isLoading = false}) =>
        buildResultRows(
          results: [game('a.sfc'), game('b.sfc')],
          remoteSectionVisible: true,
          visibleRemote: [rom(1, 'Remote One'), rom(2, 'Remote Two')],
          hasMore: hasMore,
          isLoading: isLoading,
        );

    test('the header is rendered but never focusable', () {
      final built = withRemote();

      expect(built.rows[2], isA<RemoteHeaderRow>());
      expect(built.focusable, [
        0,
        1,
        3,
        4,
      ], reason: 'row 2 is the header and has to be skipped by Up/Down');
    });

    test('selection indices resolve past the header to the right row', () {
      final built = withRemote();

      // Selection 2 is the *third focusable* row, which is the first remote
      // ROM at row index 3 — not row 2, which is the header.
      expect((built.rowAtSelection(2)! as RemoteRow).rom.name, 'Remote One');
      expect((built.rowAtSelection(3)! as RemoteRow).rom.name, 'Remote Two');
      expect((built.rowAtSelection(0)! as LocalRow).game.filename, 'a.sfc');
    });

    test('a row index maps back to its selection index across the header', () {
      final built = withRemote();

      expect(built.focusableIndexOfRow(0), 0);
      expect(built.focusableIndexOfRow(1), 1);
      expect(
        built.focusableIndexOfRow(3),
        2,
        reason: 'the first remote ROM renders at row 3 but selects at 2',
      );
      expect(built.focusableIndexOfRow(4), 3);
    });

    test('the header reports no selection index rather than a neighbour', () {
      expect(
        withRemote().focusableIndexOfRow(2),
        -1,
        reason: 'tapping the header must be a no-op, not select around it',
      );
    });

    test('round-tripping every focusable row returns that same row', () {
      final built = withRemote(hasMore: true);

      for (final rowIndex in built.focusable) {
        final selection = built.focusableIndexOfRow(rowIndex);
        expect(built.rowAtSelection(selection), same(built.rows[rowIndex]));
      }
    });

    test('load-more is focusable, the spinner is not', () {
      final loadMore = withRemote(hasMore: true);
      expect(loadMore.rows.last, isA<RemoteStatusRow>());
      expect(
        loadMore.focusable.last,
        loadMore.rows.length - 1,
        reason: 'load-more doubles as a button',
      );

      final loading = withRemote(isLoading: true);
      expect(
        loading.focusable,
        isNot(contains(loading.rows.length - 1)),
        reason: 'the spinner is not something the user can select',
      );
    });

    test('the error row is focusable so it can double as retry', () {
      final built = buildResultRows(
        results: [],
        remoteSectionVisible: true,
        hasError: true,
      );

      expect(built.rows, hasLength(2));
      expect(built.focusable, [1], reason: 'header out, error row in');
    });
  });

  group('buildResultRows remote explanations', () {
    test('an unfilterable rating replaces the remote rows with a note', () {
      final built = buildResultRows(
        results: [game('a.sfc')],
        remoteSectionVisible: true,
        rommFilterable: false,
        visibleRemote: [rom(1, 'Remote One')],
        hasMore: true,
      );

      expect(built.rows, hasLength(3));
      expect(
        (built.rows[2] as RemoteStatusRow).status,
        RemoteStatus.unsupported,
      );
      expect(built.focusable, [
        0,
      ], reason: 'the note is not selectable, and it suppresses load-more');
    });

    test('a filter RomM has no vocabulary for replaces the remote rows', () {
      final built = buildResultRows(
        results: [game('a.sfc')],
        remoteSectionVisible: true,
        unmatchedFilter: 'Role-Playing',
        visibleRemote: [rom(1, 'Remote One')],
      );

      expect(built.rows, hasLength(3));
      expect(
        (built.rows[2] as RemoteStatusRow).status,
        RemoteStatus.noEquivalent,
      );
      expect(built.focusable, [0]);
    });
  });
}
