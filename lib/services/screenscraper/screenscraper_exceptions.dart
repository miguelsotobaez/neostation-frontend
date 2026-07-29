/// Exceptions thrown by the ScreenScraper service layer.
class ScreenscraperQuotaExceededException implements Exception {
  final String message;

  ScreenscraperQuotaExceededException([this.message = '']);

  @override
  String toString() =>
      'ScreenscraperQuotaExceededException: ${message.isEmpty ? 'Daily scraping quota exceeded' : message}';
}
