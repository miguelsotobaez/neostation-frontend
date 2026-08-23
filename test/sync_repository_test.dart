import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/repositories/sync_repository.dart';

import 'database_test_helper.dart';

void main() {
  final dbHelper = DatabaseTestHelper();

  setUp(() async {
    await dbHelper.setUp();
  });

  tearDown(() async {
    await dbHelper.tearDown();
  });

  group('SyncRepository', () {
    test('getSyncState returns null when no state exists', () async {
      final state = await SyncRepository.getSyncState(
        'neosync',
        '/save/file.srm',
      );
      expect(state, isNull);
    });

    test('saveSyncState persists sync metadata', () async {
      await SyncRepository.saveSyncState(
        'neosync',
        '/save/file.srm',
        1700000000,
        1700000100,
        1024,
        fileHash: 'abc123',
      );

      final state = await SyncRepository.getSyncState(
        'neosync',
        '/save/file.srm',
      );
      expect(state, isNotNull);
      expect(state!['file_path'], '/save/file.srm');
      expect(state['local_modified_at'], 1700000000);
      expect(state['cloud_updated_at'], 1700000100);
      expect(state['file_size'], 1024);
      expect(state['file_hash'], 'abc123');
    });

    test(
      'sync state is isolated per provider for the same file path',
      () async {
        await SyncRepository.saveSyncState(
          'neosync',
          '/save/shared.srm',
          1700000000,
          1700000100,
          1024,
        );
        await SyncRepository.saveSyncState(
          'romm',
          '/save/shared.srm',
          1800000000,
          1800000100,
          2048,
        );

        final neosync = await SyncRepository.getSyncState(
          'neosync',
          '/save/shared.srm',
        );
        final romm = await SyncRepository.getSyncState(
          'romm',
          '/save/shared.srm',
        );
        expect(neosync!['cloud_updated_at'], 1700000100);
        expect(romm!['cloud_updated_at'], 1800000100);
      },
    );

    test('saveSyncState without hash allows null hash', () async {
      await SyncRepository.saveSyncState(
        'neosync',
        '/save/no_hash.srm',
        1700000000,
        1700000100,
        512,
      );

      final state = await SyncRepository.getSyncState(
        'neosync',
        '/save/no_hash.srm',
      );
      expect(state, isNotNull);
      expect(state!['file_hash'], isNull);
    });
  });
}
