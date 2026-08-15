import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';
import 'package:neostation/providers/sqlite_config_provider.dart';
import 'package:neostation/services/global_notification_service.dart';

import 'database_test_helper.dart';

/// Off Android, a scan with no configured ROM root walks nothing and used to
/// report success anyway: the library kept working from stored `rom_path`
/// rows while every scan was a silent no-op, so new files were never picked
/// up and nothing said why. Settings > Directories reads the folder table
/// directly, so a folder could still appear configured throughout.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final helper = DatabaseTestHelper();
  late DatabaseAdapter db;

  setUp(() async {
    db = await helper.setUp();
    GlobalNotificationService().dismiss();
  });

  tearDown(() async {
    await helper.tearDown();
    GlobalNotificationService().dismiss();
  });

  /// Inserts a ROM row so the library counts as non-empty.
  Future<void> storeRom() async {
    await db.rawInsert(
      'INSERT INTO user_roms (app_system_id, filename, rom_path) '
      'VALUES (?, ?, ?)',
      ['nes', 'Game.nes', '/roms/nes/Game.nes'],
    );
  }

  bool hasNoFoldersNotification() => GlobalNotificationService().notifier.value
      .any((n) => n.id == 'rom-folders-missing');

  test('aborts and reports when no ROM folder is configured', () async {
    await storeRom();
    final provider = SqliteConfigProvider();

    await provider.scanSystems();

    expect(provider.config.romFolders, isEmpty);
    expect(provider.error, contains('No ROM folder is configured'));
    expect(hasNoFoldersNotification(), isTrue);
    // The systems screen renders neither the library nor the setup prompt
    // until this flips, so an early return without it leaves a blank page.
    expect(provider.scanCompleted, isTrue);
    expect(provider.isScanning, isFalse);
  });

  test('leaves the stored ROMs in place', () async {
    await storeRom();
    final provider = SqliteConfigProvider();

    await provider.scanSystems();

    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM user_roms');
    expect(rows.first['c'], 1);
  });

  test('a fresh install with no ROMs is not an error', () async {
    final provider = SqliteConfigProvider();

    await provider.scanSystems();

    expect(hasNoFoldersNotification(), isFalse);
    expect(provider.error, isNot(contains('No ROM folder is configured')));
  });

  test('a configured folder does not trip the guard', () async {
    await storeRom();
    final romRoot = await Directory.systemTemp.createTemp('neostation_scan_');
    addTearDown(() async {
      if (await romRoot.exists()) await romRoot.delete(recursive: true);
    });
    final provider = SqliteConfigProvider();
    await provider.addRomFolder(romRoot.path, scan: false);

    await provider.scanSystems();

    expect(provider.config.romFolders, [romRoot.path]);
    expect(hasNoFoldersNotification(), isFalse);
  });
}
