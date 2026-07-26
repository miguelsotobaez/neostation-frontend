/// Secret redaction for anything written to the application log.
///
/// The log file lives on shared external storage and users routinely attach it
/// to public bug reports, so credentials must never reach it. Redaction is
/// applied centrally in [LoggerService] rather than at call sites: the leaks
/// that matter come from error objects we do not format ourselves — an HTTP
/// client exception, for example, embeds the full request URI including its
/// query string.
///
/// Kept pure and dependency-free so the patterns can be tested directly.
library;

/// Placeholder substituted for every redacted value.
const String redactedPlaceholder = '<redacted>';

/// Query-string parameters whose values are credentials.
///
/// `y` is the RetroAchievements web API key; `devpassword`/`sspassword` and
/// `devid`/`ssid` are the ScreenScraper developer and user credentials. The
/// rest are generic names used across the HTTP clients.
const List<String> _sensitiveParams = [
  'y',
  'api_key',
  'apikey',
  'access_token',
  'refresh_token',
  'auth',
  'devid',
  'devpassword',
  'key',
  'pass',
  'passwd',
  'password',
  'secret',
  'session',
  'sig',
  'signature',
  'ssid',
  'sspassword',
  'token',
];

/// `?y=abc` / `&password=abc` — keeps the parameter name, drops the value.
/// The value stops at the next separator so the rest of the URI is preserved.
final RegExp _queryParamPattern = RegExp(
  '([?&](?:${_sensitiveParams.join('|')})=)([^&\\s"\'<>)\\]}]+)',
  caseSensitive: false,
);

/// `"password": "abc"` / `password: abc` in JSON or map/toString output.
///
/// The unquoted value must also stop at `&` and `<`: without that it runs past
/// the end of a query parameter and swallows the remainder of a URL, and it
/// re-matches an already-substituted `<redacted>`, breaking idempotence.
final RegExp _jsonFieldPattern = RegExp(
  '(["\']?(?:${_sensitiveParams.join('|')})["\']?\\s*[:=]\\s*)'
  '(["\'][^"\']*["\']|[^,\\s}\\]&<>"\']+)',
  caseSensitive: false,
);

/// `Authorization: Bearer abc` and `Basic dXNlcjpwYXNz`.
final RegExp _authHeaderPattern = RegExp(
  r'((?:Bearer|Basic|Token)\s+)([A-Za-z0-9\-._~+/]+=*)',
  caseSensitive: false,
);

/// A JWT anywhere in the text, including ones we never named.
final RegExp _jwtPattern = RegExp(
  r'eyJ[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]{4,}\.[A-Za-z0-9_-]+',
);

/// Credentials embedded in a URL's userinfo: `https://user:pass@host`.
final RegExp _urlUserInfoPattern = RegExp(r'(://)[^/\s:@]+:[^/\s@]+@');

/// Returns [text] with every recognised credential replaced by
/// [redactedPlaceholder].
///
/// Non-secret content is left untouched so the log stays useful for debugging:
/// usernames, hosts, paths and endpoint names all survive.
String redactSecrets(String text) {
  if (text.isEmpty) return text;

  var result = text.replaceAllMapped(
    _queryParamPattern,
    (m) => '${m[1]}$redactedPlaceholder',
  );
  result = result.replaceAllMapped(
    _jsonFieldPattern,
    (m) => '${m[1]}$redactedPlaceholder',
  );
  result = result.replaceAllMapped(
    _authHeaderPattern,
    (m) => '${m[1]}$redactedPlaceholder',
  );
  result = result.replaceAll(_jwtPattern, redactedPlaceholder);
  result = result.replaceAllMapped(
    _urlUserInfoPattern,
    (m) => '${m[1]}$redactedPlaceholder@',
  );
  return result;
}
