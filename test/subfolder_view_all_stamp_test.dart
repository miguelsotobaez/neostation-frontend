import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/repositories/system_repository.dart';

import 'database_test_helper.dart';

/// Tests for the global "Show Subfolders" toggle's write path: one call has to
/// reach every system, including the ones the user has never opened the
/// per-system settings dialog for (they have no user_system_settings row yet).
void main() {
  final dbHelper = DatabaseTestHelper();
  late DatabaseAdapter db;

  setUp(() async {
    db = await dbHelper.setUp();
    // The last four are virtual: the game list never reads the subfolder flag
    // for them, so the stamp has to leave them alone.
    for (final id in [
      'nes',
      'snes',
      'psx',
      'all',
      'favorites',
      'music',
      'android',
    ]) {
      await db.insert('app_systems', {
        'id': id,
        'real_name': id.toUpperCase(),
        'folder_name': id,
      });
    }
  });

  tearDown(() async {
    await dbHelper.tearDown();
  });

  Future<List<Map<String, Object?>>> settingsRows() =>
      db.query('user_system_settings', orderBy: 'app_system_id');

  group('setSubfolderViewForAll', () {
    test('enables it on systems that have no settings row yet', () async {
      expect(await settingsRows(), isEmpty);

      await SystemRepository.setSubfolderViewForAll(true);

      final rows = await settingsRows();
      expect(rows.length, 3);
      expect(rows.every((r) => r['subfolder_view'] == 1), isTrue);
    });

    test('writes no row at all for virtual systems', () async {
      await SystemRepository.setSubfolderViewForAll(true);

      final ids = (await settingsRows()).map((r) => r['app_system_id']);
      expect(ids, containsAll(['nes', 'snes', 'psx']));
      expect(ids, isNot(contains('all')));
      expect(ids, isNot(contains('favorites')));
      expect(ids, isNot(contains('music')));
      expect(ids, isNot(contains('android')));
    });

    test('leaves an existing virtual-system row untouched', () async {
      // A row can pre-date the exclusion (an early build stamped them).
      await SystemRepository.setSubfolderView('music', true);

      await SystemRepository.setSubfolderViewForAll(false);

      final rows = await settingsRows();
      final byId = {for (final r in rows) r['app_system_id']: r};
      expect(byId['music']!['subfolder_view'], 1);
      expect(byId['nes']!['subfolder_view'], 0);
    });

    test('overwrites a system that was configured by hand', () async {
      await SystemRepository.setSubfolderView('nes', true);

      await SystemRepository.setSubfolderViewForAll(false);

      final rows = await settingsRows();
      expect(rows.length, 3);
      expect(rows.every((r) => r['subfolder_view'] == 0), isTrue);
    });

    test('a system keeps its own toggle after the global stamp', () async {
      await SystemRepository.setSubfolderViewForAll(true);
      await SystemRepository.setSubfolderView('snes', false);

      final rows = await settingsRows();
      final byId = {for (final r in rows) r['app_system_id']: r};
      expect(byId['nes']!['subfolder_view'], 1);
      expect(byId['snes']!['subfolder_view'], 0);
      expect(byId['psx']!['subfolder_view'], 1);
    });

    test('leaves the other per-system settings at their defaults', () async {
      await SystemRepository.setSubfolderViewForAll(true);

      final row = (await settingsRows()).first;
      // The inserted row names only subfolder_view, so everything else has to
      // read exactly as the absent row did.
      expect(row['recursive_scan'], 1);
      expect(row['hide_extension'], 1);
      expect(row['hide_parentheses'], 1);
      expect(row['hide_brackets'], 1);
      expect(row['hide_logo'], 0);
      expect(row['prefer_file_name'], 0);
    });

    test('re-stamping the same value is idempotent', () async {
      await SystemRepository.setSubfolderViewForAll(true);
      await SystemRepository.setSubfolderViewForAll(true);

      final rows = await settingsRows();
      expect(rows.length, 3);
      expect(rows.every((r) => r['subfolder_view'] == 1), isTrue);
    });
  });

  group('countSubfolderViewOverrides', () {
    test('counts nothing when every system agrees with the global', () async {
      expect(await SystemRepository.countSubfolderViewOverrides(false), 0);

      await SystemRepository.setSubfolderViewForAll(true);

      expect(await SystemRepository.countSubfolderViewOverrides(true), 0);
    });

    test('counts a system set by hand against a global that is off', () async {
      await SystemRepository.setSubfolderView('nes', true);

      expect(await SystemRepository.countSubfolderViewOverrides(false), 1);
    });

    test('counts a system turned off under a global that is on', () async {
      await SystemRepository.setSubfolderViewForAll(true);
      await SystemRepository.setSubfolderView('snes', false);

      expect(await SystemRepository.countSubfolderViewOverrides(true), 1);
    });

    test('a system with no row counts as off, not as a deviation', () async {
      // Nothing has ever been written, so no system deviates from "off" — but
      // every one of them deviates from "on".
      expect(await SystemRepository.countSubfolderViewOverrides(false), 0);
      expect(await SystemRepository.countSubfolderViewOverrides(true), 3);
    });

    test('never counts a virtual system', () async {
      await SystemRepository.setSubfolderView('music', true);
      await SystemRepository.setSubfolderView('all', true);

      expect(await SystemRepository.countSubfolderViewOverrides(false), 0);
    });
  });
}
