import '../../repositories/scraper_repository.dart';

/// Region-priority resolution for ScreenScraper media/text selection.
///
/// Owns the default region ordering and builds the priority map used when
/// picking the best regional asset for a game. Extracted verbatim from
/// [ScreenScraperService] as the first step of the facade decomposition;
/// behaviour is unchanged.
class ScreenscraperRegionConfig {
  ScreenscraperRegionConfig._();

  static const List<String> _defaultRegionOrder = [
    'wor',
    'us',
    'eu',
    'jp',
    'sp',
    'fr',
    'de',
    'it',
    'kr',
    'cn',
  ];

  static Map<String, int> _buildRegionPriorityMap(List<String> orderedRegions) {
    return {
      for (var i = 0; i < orderedRegions.length; i++)
        orderedRegions[i]: (orderedRegions.length - i) * 10,
    };
  }

  static Future<Map<String, int>> getRegionPriority() async {
    try {
      final regions = await ScraperRepository.getRegionPriority();
      if (regions.isNotEmpty) return _buildRegionPriorityMap(regions);
    } catch (_) {}
    return _buildRegionPriorityMap(_defaultRegionOrder);
  }
}
