import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:neostation/data/datasources/sqlite_service.dart';

/// Pins the startup scan that reports a system with more than one user-selected
/// default emulator.
///
/// The scan used to count *joined rows*. `app_emulators` is keyed on
/// `(os_id, unique_identifier)`, so a single user choice fans out to one row per
/// operating system the emulator is defined for, and a healthy database was
/// reported as broken — "system=ps1 has 4 user defaults" for one DuckStation
/// pick defined on four platforms.
void main() {
  late sqlite.Database db;
  late DatabaseAdapter adapter;

  setUp(() {
    db = sqlite.sqlite3.openInMemory();
    adapter = DatabaseAdapter(db);
    db.execute('''
      CREATE TABLE app_emulators (
        unique_identifier TEXT NOT NULL,
        os_id INTEGER NOT NULL,
        system_id TEXT NOT NULL,
        PRIMARY KEY (os_id, unique_identifier)
      )
    ''');
    db.execute('''
      CREATE TABLE user_emulator_config (
        emulator_unique_id TEXT NOT NULL,
        emulator_path TEXT NOT NULL,
        is_user_default INTEGER DEFAULT NULL,
        PRIMARY KEY (emulator_unique_id)
      )
    ''');
  });

  tearDown(() => db.close());

  /// Registers [uniqueId] for [systemId] on each of [osIds], the way the
  /// systems JSON does for every platform an emulator declares.
  void defineEmulator(String uniqueId, String systemId, List<int> osIds) {
    for (final osId in osIds) {
      db.execute(
        'INSERT INTO app_emulators (unique_identifier, os_id, system_id) '
        'VALUES (?, ?, ?)',
        [uniqueId, osId, systemId],
      );
    }
  }

  void chooseAsDefault(String uniqueId) {
    db.execute(
      'INSERT INTO user_emulator_config '
      '(emulator_unique_id, emulator_path, is_user_default) VALUES (?, ?, 1)',
      [uniqueId, ''],
    );
  }

  group('findDuplicateUserDefaults', () {
    test(
      'one choice defined for several platforms is not an anomaly',
      () async {
        // The exact false positive: standalone DuckStation declares android,
        // windows, linux and macos in assets/systems/ps1.json, so the join
        // returned four rows for one deliberate choice.
        defineEmulator('ps1.com.github.stenzek.duckstation', 'ps1', [
          1,
          2,
          3,
          4,
        ]);
        chooseAsDefault('ps1.com.github.stenzek.duckstation');

        expect(
          await SqliteService.findDuplicateUserDefaults(adapter),
          isEmpty,
          reason: 'a healthy single choice must never be reported as broken',
        );
      },
    );

    test('two different emulators for one system is an anomaly', () async {
      // The real violation the scan exists to catch: whichever row the
      // LIMIT 1 lookup happens to return wins, so the launch is a coin toss.
      defineEmulator('ps1.com.github.stenzek.duckstation', 'ps1', [1, 2]);
      defineEmulator('ps1.com.epsxe.ePSXe', 'ps1', [1, 2]);
      chooseAsDefault('ps1.com.github.stenzek.duckstation');
      chooseAsDefault('ps1.com.epsxe.ePSXe');

      final anomalies = await SqliteService.findDuplicateUserDefaults(adapter);

      expect(anomalies.keys, ['ps1']);
      expect(
        anomalies['ps1'],
        containsAll([
          'ps1.com.github.stenzek.duckstation',
          'ps1.com.epsxe.ePSXe',
        ]),
      );
    });

    test('reports only the offending system', () async {
      defineEmulator('ps1.duckstation', 'ps1', [1, 2, 3, 4]);
      chooseAsDefault('ps1.duckstation');

      defineEmulator('nds.melonds', 'nds', [1, 2]);
      defineEmulator('nds.drastic', 'nds', [2]);
      chooseAsDefault('nds.melonds');
      chooseAsDefault('nds.drastic');

      final anomalies = await SqliteService.findDuplicateUserDefaults(adapter);

      expect(anomalies.keys, ['nds']);
    });

    test('a database with no user choices is silent', () async {
      defineEmulator('ps1.duckstation', 'ps1', [1, 2, 3, 4]);

      expect(await SqliteService.findDuplicateUserDefaults(adapter), isEmpty);
    });

    test('a cleared choice does not count', () async {
      defineEmulator('ps1.duckstation', 'ps1', [1, 2]);
      defineEmulator('ps1.epsxe', 'ps1', [1, 2]);
      chooseAsDefault('ps1.duckstation');
      db.execute(
        'INSERT INTO user_emulator_config '
        '(emulator_unique_id, emulator_path, is_user_default) VALUES (?, ?, 0)',
        ['ps1.epsxe', ''],
      );

      expect(await SqliteService.findDuplicateUserDefaults(adapter), isEmpty);
    });
  });
}
