import 'package:flutter_test/flutter_test.dart';
import 'package:neostation/services/screenscraper/media_resolver.dart';

void main() {
  group('ScreenScraper manual media', () {
    test('maps ScreenScraper manuel media to the manuals folder', () {
      expect(
        ScreenscraperMediaResolver.mapMediaTypeToFolder('manuel'),
        'manuals',
      );
    });

    test('prefers a manual matching the configured language', () {
      final medias = <Map<String, dynamic>>[
        {
          'type': 'manuel',
          'region': 'wor',
          'langue': 'en',
          'format': 'pdf',
          'url': 'https://example.invalid/en.pdf',
        },
        {
          'type': 'manuel',
          'region': 'eu',
          'langue': 'fr',
          'format': 'pdf',
          'url': 'https://example.invalid/fr.pdf',
        },
      ];

      final selected = ScreenscraperMediaResolver.selectBestMedia(
        medias,
        'manuel',
        preferredLanguage: 'fr',
        regionPriority: const {'wor': 100, 'eu': 80},
      );

      expect(selected?['langue'], 'fr');
      expect(selected?['format'], 'pdf');
    });
  });
}
