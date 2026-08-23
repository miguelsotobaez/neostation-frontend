import 'package:flutter_test/flutter_test.dart';

import 'package:neostation/models/neo_sync_models.dart';

void main() {
  group('NeoSyncFileFilter.toQueryParameters', () {
    test('omits empty values', () {
      const filter = NeoSyncFileFilter();
      expect(filter.toQueryParameters(), isEmpty);
    });

    test('includes every populated dimension', () {
      const filter = NeoSyncFileFilter(
        limit: 50,
        offset: 100,
        scope: 'game',
        system: 'gba',
        emulator: 'mGBA',
        state: true,
        query: 'Crash',
        sort: 'name',
        dir: 'asc',
      );
      expect(filter.toQueryParameters(), {
        'limit': '50',
        'offset': '100',
        'scope': 'game',
        'system': 'gba',
        'emulator': 'mGBA',
        'state': 'true',
        'q': 'Crash',
        'sort': 'name',
        'dir': 'asc',
      });
    });

    test('trims and drops a blank search query', () {
      const filter = NeoSyncFileFilter(query: '   ');
      expect(filter.toQueryParameters(), isEmpty);
    });
  });

  group('NeoSyncFileFilter.copyWith', () {
    test('keeps untouched fields', () {
      const filter = NeoSyncFileFilter(system: 'ps2', emulator: 'PCSX2');
      final updated = filter.copyWith(scope: 'shared');
      expect(updated.system, 'ps2');
      expect(updated.emulator, 'PCSX2');
      expect(updated.scope, 'shared');
    });

    test('clears a field back to "Any" when passed null', () {
      const filter = NeoSyncFileFilter(scope: 'game', system: 'gba');
      final updated = filter.copyWith(scope: null);
      expect(updated.scope, isNull);
      expect(updated.system, 'gba');
    });

    test('clears pagination when passed null', () {
      const filter = NeoSyncFileFilter(limit: 50, offset: 100);
      final updated = filter.copyWith(limit: null, offset: null);
      expect(updated.limit, isNull);
      expect(updated.offset, isNull);
    });
  });
}
