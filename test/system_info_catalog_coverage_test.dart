import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every bundled system definition contains rich System Info metadata', () {
    final systemFiles = Directory('assets/systems')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList();

    expect(systemFiles, isNotEmpty);

    final definitions = <String, Map<String, dynamic>>{};
    for (final file in systemFiles) {
      final root = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final system = Map<String, dynamic>.from(root['system'] as Map);
      definitions[system['id'].toString()] = system;
    }

    for (final entry in definitions.entries) {
      final id = entry.key;
      final system = entry.value;
      final details = Map<String, dynamic>.from(system['details'] as Map? ?? {});
      final parent = details['info_inherits']?.toString();
      final collectionKind = details['collection_kind']?.toString();
      final notableGames = (details['notable_games'] as List?) ?? const [];
      final media = (details['media'] as List?) ?? const [];

      final hasDirectRichInfo =
          (details['architecture']?.toString().isNotEmpty ?? false) ||
          details['generation'] != null ||
          (details['cpu']?.toString().isNotEmpty ?? false) ||
          media.isNotEmpty ||
          notableGames.isNotEmpty ||
          (collectionKind?.isNotEmpty ?? false);

      expect(
        hasDirectRichInfo || (parent?.isNotEmpty ?? false),
        isTrue,
        reason: '$id has no rich System Info metadata',
      );

      if (parent != null && parent.isNotEmpty) {
        expect(
          definitions.containsKey(parent),
          isTrue,
          reason: '$id inherits missing system $parent',
        );
      }

      expect(
        notableGames.every((game) => game.toString().trim().isNotEmpty),
        isTrue,
        reason: '$id contains an empty notable game title',
      );
      expect(
        media.every((item) => item.toString().trim().isNotEmpty),
        isTrue,
        reason: '$id contains an empty media identifier',
      );
    }

    // Inheritance is intentionally used by hack/variant definitions. Guard
    // against accidental cycles so a future system-definition update cannot
    // make SystemInfoCatalog recurse forever.
    for (final id in definitions.keys) {
      final seen = <String>{};
      var current = id;
      while (true) {
        expect(seen.add(current), isTrue, reason: 'inheritance cycle at $id');
        final details = Map<String, dynamic>.from(
          definitions[current]?['details'] as Map? ?? {},
        );
        final parent = details['info_inherits']?.toString();
        if (parent == null || parent.isEmpty) break;
        current = parent;
      }
    }
  });
}
