import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_database_service.dart';

/// The native fast SAF walk answers a directory it could not read the same way
/// it answers one that is genuinely empty, and the scan reads "no files" as
/// "every ROM for this system was deleted". Before an empty fast walk is
/// believed, the DocumentsProvider is asked for a second opinion; these cover
/// what counts as a contradiction.
///
/// Reported by a user whose whole library vanished behind this: 120 populated
/// ROM directories all reported `fast walk found 0 entries (empty, non-null)`
/// while the same tree listed 178 subfolders through the DocumentsProvider.
void main() {
  Map<String, dynamic> file(String name, {bool hidden = false}) => {
    'name': name,
    'uri': 'content://tree/primary%3AROMs/document/primary%3AROMs%2F$name',
    'isDirectory': false,
    'isHidden': hidden,
  };

  Map<String, dynamic> dir(String name) => {
    'name': name,
    'uri': 'content://tree/primary%3AROMs/document/primary%3AROMs%2F$name',
    'isDirectory': true,
    'isHidden': false,
  };

  group('visibleSafChildren', () {
    test('a directory the provider also sees as empty stays empty', () {
      expect(SqliteDatabaseService.visibleSafChildren(const []), isEmpty);
    });

    test('a file the fast walk missed contradicts it', () {
      expect(
        SqliteDatabaseService.visibleSafChildren([file('Sonic.md')]),
        hasLength(1),
      );
    });

    test('a subdirectory contradicts it too', () {
      // A non-recursive scan finds no files in a directory of directories, but
      // the fast walk claiming *nothing* is there is still unusable: recursion
      // is exactly where a failed listing hides the most.
      expect(
        SqliteDatabaseService.visibleSafChildren([dir('Disc 1')]),
        hasLength(1),
      );
    });

    test('a folder holding only hidden entries reads as empty', () {
      // Otherwise every .nomedia-only folder pays for the slow walk on every
      // scan and gains nothing: it holds no ROMs either way.
      expect(
        SqliteDatabaseService.visibleSafChildren([
          file('.nomedia'),
          file('cover.png', hidden: true),
        ]),
        isEmpty,
      );
    });

    test('hidden entries count once the user asks to see them', () {
      expect(
        SqliteDatabaseService.visibleSafChildren([
          file('.hidden.nes'),
        ], ignoreHiddenFiles: false),
        hasLength(1),
      );
    });

    test('a hidden entry does not mask a real one beside it', () {
      expect(
        SqliteDatabaseService.visibleSafChildren([
          file('.nomedia'),
          file('Sonic.md'),
        ]),
        hasLength(1),
      );
    });
  });
}
