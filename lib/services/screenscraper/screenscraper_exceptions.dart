/// Exceptions thrown by the ScreenScraper service layer.
class ScreenscraperQuotaExceededException implements Exception {
  final String message;

  ScreenscraperQuotaExceededException([this.message = '']);

  @override
  String toString() =>
      'ScreenscraperQuotaExceededException: ${message.isEmpty ? 'Daily scraping quota exceeded' : message}';
}

/// Thrown when a request waited too long for a slot in the concurrency
/// semaphore. Under normal load a slot frees up in well under a second, so
/// hitting this means slots have been leaked (or a request is wedged) — and
/// without it the caller would simply hang forever with no error to show,
/// which is exactly what a scrape or a login screen must never do.
class ScreenscraperSemaphoreTimeoutException implements Exception {
  final String message;

  ScreenscraperSemaphoreTimeoutException([this.message = '']);

  @override
  String toString() =>
      'ScreenscraperSemaphoreTimeoutException: ${message.isEmpty ? 'Timed out waiting for a request slot' : message}';
}
