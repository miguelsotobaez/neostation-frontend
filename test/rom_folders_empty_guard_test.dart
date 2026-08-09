import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';

import 'database_test_helper.dart';

/// A blanket config save must never be able to wipe the configured ROM
/// folders. `saveConfig` hands `saveUserRomFolders` whatever `romFolders` its
/// config object carries, and an empty list there means "this object never had
/// them" rather than "the user removed them" - removal has its own API.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final helper = DatabaseTestHelper();

  setUp(() async {
    await helper.setUp();
  });

  tearDown(() async {
    await helper.tearDown();
  });

  Future<List<String>> storedFolders() async {
    return SqliteService.getUserRomFolders();
  }

  test('saving an empty list keeps the configured folders', () async {
    await SqliteService.saveUserRomFolders(['/roms', '/sdcard/roms']);
    expect(await storedFolders(), ['/roms', '/sdcard/roms']);

    await SqliteService.saveUserRomFolders([]);

    expect(await storedFolders(), ['/roms', '/sdcard/roms']);
  });

  test('a list of only empty paths keeps the configured folders', () async {
    await SqliteService.saveUserRomFolders(['/roms']);

    await SqliteService.saveUserRomFolders(['', '']);

    expect(await storedFolders(), ['/roms']);
  });

  test('an empty list is a no-op when nothing is configured', () async {
    await SqliteService.saveUserRomFolders([]);

    expect(await storedFolders(), isEmpty);
  });

  test('a non-empty list still replaces the existing folders', () async {
    await SqliteService.saveUserRomFolders(['/old', '/also-old']);

    await SqliteService.saveUserRomFolders(['/new']);

    expect(await storedFolders(), ['/new']);
  });

  test('empty entries are dropped from a non-empty list', () async {
    await SqliteService.saveUserRomFolders(['/roms', '', '/more-roms']);

    expect(await storedFolders(), ['/roms', '/more-roms']);
  });
}
