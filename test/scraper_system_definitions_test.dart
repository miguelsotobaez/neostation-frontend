import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows, Steam, and Xbox definitions include supported game files', () {
    final expectedExtensions = <String, Set<String>>{
      'windows.json': {'exe', 'steam'},
      'steam.json': {'steam'},
      'xbox.json': {'xbe', 'iso'},
      'xbox360.json': {'xex'},
    };

    for (final entry in expectedExtensions.entries) {
      final file = File('assets/systems/${entry.key}');
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final system = json['system'] as Map<String, dynamic>;
      final extensions = (system['extensions'] as List<dynamic>)
          .map((extension) => extension.toString().toLowerCase())
          .toSet();

      expect(
        extensions,
        containsAll(entry.value),
        reason:
            '${entry.key} must include executable game files so they are '
            'detected and passed to ScreenScraper.',
      );
    }
  });
}
