import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:neostation/data/datasources/sqlite_service.dart';

/// Tests for [DatabaseAdapter.transaction]'s serialization.
///
/// Every caller shares one connection and `package:sqlite3` is synchronous, so
/// a transaction body that awaits used to let an unrelated task run its
/// statements inside the open transaction. The second task returned success
/// with nothing committed, and the first task's rollback discarded its work.
void main() {
  late Database db;
  late DatabaseAdapter adapter;

  setUp(() {
    db = sqlite3.openInMemory();
    db.execute('''
      CREATE TABLE user_rom_folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        path TEXT NOT NULL UNIQUE
      )
    ''');
    adapter = DatabaseAdapter(db);
  });

  tearDown(() {
    db.close();
  });

  int rowCount() =>
      db.select('SELECT COUNT(*) AS c FROM user_rom_folders').first['c'] as int;

  /// The shape of `saveUserRomFolders`: replace the table's contents wholesale.
  Future<void> replaceFolders(List<String> paths) {
    return adapter.transaction((txn) async {
      await txn.delete('user_rom_folders');
      for (final path in paths) {
        await txn.insert('user_rom_folders', {'path': path});
      }
    });
  }

  group('concurrent transactions', () {
    test('overlapping writers do not share one transaction', () async {
      const folder = 'content://tree/primary%3AROMs';
      await replaceFolders([folder]);

      // Started together and awaited together: the second call enters while the
      // first is suspended mid-transaction. Before serialization the second
      // re-inserted the row the first had already deleted, and the first's own
      // insert then failed with UNIQUE constraint failed (code 2067).
      await Future.wait([
        replaceFolders([folder]),
        replaceFolders([folder]),
      ]);

      expect(rowCount(), 1);
    });

    test('a failing transaction does not roll back a concurrent one', () async {
      await adapter.execute(
        "INSERT INTO user_rom_folders (path) VALUES ('seed')",
      );

      final failing = adapter.transaction((txn) async {
        await txn.insert('user_rom_folders', {'path': 'from-failing'});
        await Future<void>.delayed(Duration.zero);
        throw StateError('boom');
      });

      final succeeding = adapter.transaction((txn) async {
        await txn.insert('user_rom_folders', {'path': 'from-succeeding'});
      });

      await expectLater(failing, throwsStateError);
      await succeeding;

      final paths = db
          .select('SELECT path FROM user_rom_folders ORDER BY path')
          .map((row) => row['path'].toString())
          .toList();

      // The failing transaction takes only its own row with it.
      expect(paths, ['from-succeeding', 'seed']);
    });

    test('transactions commit in the order they were started', () async {
      final order = <int>[];
      await Future.wait([
        for (var i = 0; i < 5; i++)
          adapter.transaction((txn) async {
            await txn.insert('user_rom_folders', {'path': 'folder-$i'});
            await Future<void>.delayed(Duration.zero);
            order.add(i);
          }),
      ]);

      expect(order, [0, 1, 2, 3, 4]);
      expect(rowCount(), 5);
    });
  });

  group('nested transactions', () {
    // First-run setup nests three deep (_onCreate -> _insertInitialData ->
    // _executeSqlFileOptimized), so the lock has to let the owning task back in
    // rather than deadlock on itself.
    test('a nested transaction runs inline on the outer one', () async {
      await adapter.transaction((outer) async {
        await outer.insert('user_rom_folders', {'path': 'outer'});
        await adapter.transaction((inner) async {
          await inner.insert('user_rom_folders', {'path': 'inner'});
        });
      });

      expect(rowCount(), 2);
    });

    test('nesting three deep completes', () async {
      await adapter.transaction((_) async {
        await adapter.transaction((_) async {
          await adapter.transaction((txn) async {
            await txn.insert('user_rom_folders', {'path': 'deep'});
          });
        });
      });

      expect(rowCount(), 1);
    });

    test('an outer rollback discards the nested work too', () async {
      await expectLater(
        adapter.transaction((outer) async {
          await outer.insert('user_rom_folders', {'path': 'outer'});
          await adapter.transaction((inner) async {
            await inner.insert('user_rom_folders', {'path': 'inner'});
          });
          throw StateError('boom');
        }),
        throwsStateError,
      );

      expect(rowCount(), 0);
    });

    test('the lock is released after a nested failure', () async {
      await expectLater(
        adapter.transaction((_) async {
          await adapter.transaction((_) async {
            throw StateError('boom');
          });
        }),
        throwsStateError,
      );

      // Would hang if the failure path leaked the semaphore slot.
      await replaceFolders(['after']);
      expect(rowCount(), 1);
    });
  });
}
