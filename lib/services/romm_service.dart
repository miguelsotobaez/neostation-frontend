import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as path;

import '../models/romm_asset.dart';
import '../models/romm_collection.dart';
import '../models/romm_platform.dart';
import '../models/romm_rom_page.dart';
import '../models/romm_play_session.dart';
import '../models/romm_rom.dart';
import 'logger_service.dart';

/// Raised when a RomM API call fails; [message] is safe to surface to the user.
class RommException implements Exception {
  final String message;
  final int? statusCode;
  RommException(this.message, {this.statusCode});

  @override
  String toString() => 'RommException($statusCode): $message';
}

/// Raised when a download is aborted because the caller's `shouldCancel`
/// callback returned true. A distinct type (rather than matching on the
/// message string) lets callers reliably tell a user-cancelled download apart
/// from a genuine failure, even if the message is later reworded/localized.
class RommCancelledException extends RommException {
  RommCancelledException([super.message = 'Download cancelled']);
}

/// HTTP client for a remote RomM server (library browse + ROM download).
///
/// Holds the server base URL and JWT tokens for one connection and transparently
/// refreshes the access token on expiry / 401. Auth is OAuth2 password grant
/// (`POST /api/token`). Modeled on the IOClient + bad-certificate setup used by
/// [ScreenScraperService] so self-signed homelab certificates work.
class RommService {
  static final _log = LoggerService.instance;

  /// Scopes requested in the password grant. RomM grants the intersection of
  /// these and the user's allowed scopes; covers library browse + download plus
  /// save/state sync (`assets.write`).
  static const String _readScopes =
      'me.read roms.read platforms.read assets.read assets.write collections.read firmware.read';

  /// Extra scopes needed for playtime sync (`/api/play-sessions`). Requested on
  /// top of [_readScopes], but *optionally*: RomM's token endpoint rejects the
  /// whole grant with a 403 if any requested scope is outside the user's
  /// allowance, and these two don't exist at all on servers older than the
  /// play-session feature. [authenticate] therefore falls back to the base
  /// scope set rather than turning "no playtime sync" into "cannot log in".
  static const String _playtimeScopes = 'roms.user.read roms.user.write';

  /// Maximum sessions RomM accepts in one `/api/play-sessions` POST.
  static const int maxPlaySessionBatch = 100;

  /// Shared client that tolerates self-signed certificates (homelab servers).
  static final http.Client _httpClient = () {
    final inner = HttpClient()
      ..badCertificateCallback =
          ((X509Certificate cert, String host, int port) => true);
    return IOClient(inner);
  }();

  String _baseUrl = '';

  /// Whether the user pinned the scheme (`http://`/`https://`) themselves. When
  /// false we may transparently downgrade an https attempt to http on a TLS
  /// handshake failure (common for plain-HTTP homelab servers).
  bool _schemeExplicit = false;
  String _username = '';
  String _password = '';
  String? _accessToken;
  String? _refreshToken;
  int? _tokenExpiresMs;

  /// Whether the server granted the playtime scopes at the last authentication.
  /// Starts optimistic: a token restored from disk may predate the scopes, and
  /// the shared 403-retry re-authenticates (picking them up) before giving up.
  bool _playtimeScopeGranted = true;

  /// Cleared for the rest of this connection once the server proves it has no
  /// play-session API (404) or won't grant access to it (403 after a re-auth),
  /// so a RomM older than the feature isn't probed on every sync.
  bool _playSessionsSupported = true;

  /// Whether playtime sync can be attempted against this server.
  bool get playtimeSyncAvailable =>
      _playtimeScopeGranted && _playSessionsSupported;

  String get baseUrl => _baseUrl;
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  int? get tokenExpiresMs => _tokenExpiresMs;

  /// Configures the connection. [serverUrl] may include or omit a scheme and
  /// trailing slash; it is normalized to `scheme://host[:port]` with no
  /// trailing slash. Existing tokens (if any) can be restored via
  /// [accessToken]/[refreshToken]/[tokenExpiresMs].
  void configure({
    required String serverUrl,
    required String username,
    required String password,
    String? accessToken,
    String? refreshToken,
    int? tokenExpiresMs,
  }) {
    final raw = serverUrl.trim();
    _schemeExplicit = raw.startsWith('http://') || raw.startsWith('https://');
    _baseUrl = _normalizeBaseUrl(raw);
    _username = username;
    _password = password;
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _tokenExpiresMs = tokenExpiresMs;
    // Playtime support is a property of the server we're pointed at, so a
    // reconfigure (different server, or the same one after an edit) re-probes
    // instead of inheriting the previous server's verdict.
    _playtimeScopeGranted = true;
    _playSessionsSupported = true;
  }

  static String _normalizeBaseUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  Uri _uri(String pathAndQuery) => Uri.parse('$_baseUrl$pathAndQuery');

  bool get _tokenLikelyValid {
    if (_accessToken == null || _accessToken!.isEmpty) return false;
    final exp = _tokenExpiresMs;
    if (exp == null) return true; // assume valid until a 401 proves otherwise
    // Refresh 30s early to avoid edge-of-expiry races.
    return DateTime.now().millisecondsSinceEpoch < exp - 30000;
  }

  // ── Authentication ─────────────────────────────────────────────────────────

  /// POSTs to `/api/token`. If an HTTPS TLS handshake fails and the user did
  /// not pin the scheme, downgrades the base URL to HTTP and retries once
  /// (plain-HTTP homelab servers are common).
  Future<http.Response> _postTokenRequest(Map<String, String> body) async {
    const headers = {'Content-Type': 'application/x-www-form-urlencoded'};
    try {
      return await _httpClient
          .post(_uri('/api/token'), headers: headers, body: body)
          .timeout(const Duration(seconds: 30));
    } on HandshakeException {
      if (!_schemeExplicit && _baseUrl.startsWith('https://')) {
        _baseUrl = _baseUrl.replaceFirst('https://', 'http://');
        _log.w('RomM HTTPS handshake failed; retrying over HTTP at $_baseUrl');
        return await _httpClient
            .post(_uri('/api/token'), headers: headers, body: body)
            .timeout(const Duration(seconds: 30));
      }
      rethrow;
    }
  }

  /// Performs the OAuth2 password grant and stores the resulting tokens.
  /// Throws [RommException] with a user-facing message on failure.
  Future<void> authenticate() async {
    if (_baseUrl.isEmpty) {
      throw RommException('Server URL is empty');
    }
    Map<String, String> bodyFor(String scope) => {
      'grant_type': 'password',
      'username': _username,
      'password': _password,
      // RomM issues an empty-scope token (403 on every read endpoint) unless
      // the requested scopes are passed explicitly.
      'scope': scope,
    };

    http.Response resp;
    try {
      resp = await _postTokenRequest(bodyFor('$_readScopes $_playtimeScopes'));
      if (resp.statusCode == 403) {
        // Either the account lacks the playtime scopes or the server predates
        // them — indistinguishable here, and both mean the same thing: keep the
        // connection, drop playtime sync. Bad credentials fail the retry too,
        // so the error path below is unchanged for them.
        final base = await _postTokenRequest(bodyFor(_readScopes));
        if (base.statusCode == 200) {
          _playtimeScopeGranted = false;
          _log.w('RomM denied $_playtimeScopes — playtime sync disabled');
        }
        resp = base.statusCode == 200 ? base : resp;
      } else if (resp.statusCode == 200) {
        _playtimeScopeGranted = true;
      }
    } on TimeoutException {
      throw RommException('Connection timed out');
    } on HandshakeException {
      throw RommException(
        'TLS handshake failed — try an http:// URL if the server is not HTTPS',
      );
    } on SocketException catch (e) {
      throw RommException('Cannot reach server: ${e.message}');
    } catch (e) {
      throw RommException('Connection failed: $e');
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw RommException(
        'Invalid username or password',
        statusCode: resp.statusCode,
      );
    }
    if (resp.statusCode != 200) {
      throw RommException(
        'Authentication failed (${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }

    _applyTokenResponse(resp.body);
  }

  Future<void> _refreshAccessToken() async {
    final refresh = _refreshToken;
    if (refresh == null || refresh.isEmpty) {
      // No refresh token: fall back to a full re-authentication.
      await authenticate();
      return;
    }
    try {
      final resp = await _postTokenRequest({
        'grant_type': 'refresh_token',
        'refresh_token': refresh,
      });
      if (resp.statusCode == 200) {
        _applyTokenResponse(resp.body);
        return;
      }
    } catch (e) {
      _log.w('RomM token refresh failed, re-authenticating: $e');
    }
    // Refresh failed for any reason: re-authenticate from credentials.
    await authenticate();
  }

  void _applyTokenResponse(String responseBody) {
    final json = jsonDecode(responseBody) as Map<String, dynamic>;
    final access = json['access_token']?.toString();
    if (access == null || access.isEmpty) {
      throw RommException('Server did not return an access token');
    }
    _accessToken = access;
    final refresh = json['refresh_token']?.toString();
    if (refresh != null && refresh.isNotEmpty) {
      _refreshToken = refresh;
    }
    // `expires` is the access-token lifetime in seconds.
    final expiresSeconds = (json['expires'] as num?)?.toInt();
    _tokenExpiresMs = expiresSeconds != null
        ? DateTime.now().millisecondsSinceEpoch + expiresSeconds * 1000
        : null;
  }

  /// Ensures a usable access token, authenticating or refreshing as needed.
  Future<void> _ensureToken() async {
    if (_tokenLikelyValid) return;
    if (_accessToken != null && _refreshToken != null) {
      await _refreshAccessToken();
    } else {
      await authenticate();
    }
  }

  Map<String, String> get _authHeaders => {
    'Authorization': 'Bearer $_accessToken',
  };

  /// Authenticates and performs a lightweight call to confirm the connection
  /// and credentials are valid (used by the settings "Test" button).
  Future<void> verifyConnection() async {
    await authenticate();
    // A successful, authorized call confirms the token works end-to-end. Hit
    // the lightweight `/api/users/me` rather than downloading the full platform
    // list — same auth guarantee, a fraction of the payload. Error mapping is
    // unchanged: authenticate() surfaces bad credentials as 401/403, and any
    // other failure surfaces as the shared "Request failed"/network message.
    await _authedGet('/api/users/me');
  }

  // ── Read endpoints ───────────────────────────────────────────────────────

  /// Sends an authenticated request via [send] and retries it once on an auth
  /// failure: `401` → refresh the access token, `403` → full re-authenticate
  /// (covers a cached token minted before the current scope set). [send] must
  /// build a *fresh* request each call so the retry picks up the new token.
  ///
  /// Works for both [http.Response] and [http.StreamedResponse] via [statusOf];
  /// this is the single retry policy shared by every authenticated call site
  /// (plain GETs, asset GETs, uploads and ROM downloads).
  Future<T> _sendWithAuthRetry<T>(
    Future<T> Function() send, {
    required int Function(T resp) statusOf,
  }) async {
    await _ensureToken();
    T resp;
    try {
      resp = await send();
    } on TimeoutException {
      throw RommException('Request timed out');
    } on SocketException catch (e) {
      throw RommException('Cannot reach server: ${e.message}');
    }
    if (statusOf(resp) == 401) {
      await _refreshAccessToken();
      resp = await send();
    } else if (statusOf(resp) == 403) {
      await authenticate();
      resp = await send();
    }
    return resp;
  }

  /// Issues an authenticated GET for a server-relative path+query, applying the
  /// shared [_sendWithAuthRetry] policy and throwing on any non-200.
  Future<http.Response> _authedGet(String pathAndQuery) =>
      _authedGetUri(_uri(pathAndQuery));

  /// Like [_authedGet] but for a fully-built [uri] (used where query parameters
  /// are assembled via [Uri] or the asset path needs bespoke encoding).
  Future<http.Response> _authedGetUri(
    Uri uri, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final resp = await _sendWithAuthRetry<http.Response>(
      () => _httpClient.get(uri, headers: _authHeaders).timeout(timeout),
      statusOf: (r) => r.statusCode,
    );
    if (resp.statusCode != 200) {
      throw RommException(
        'Request failed (${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }
    return resp;
  }

  /// Extracts the item list from a RomM list response, tolerating both a bare
  /// JSON array and a paginated `{items: [...]}` envelope. Any other shape
  /// (including `{}`) yields an empty list.
  static List<dynamic> _itemsOf(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map && decoded['items'] is List) {
      return decoded['items'] as List;
    }
    return const [];
  }

  /// Returns all platforms (consoles/systems) on the server.
  Future<List<RommPlatform>> getPlatforms() async {
    final resp = await _authedGet('/api/platforms');
    final decoded = jsonDecode(resp.body);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map<String, dynamic>>()
        .map(RommPlatform.fromJson)
        // RomM's /api/platforms returns every platform its DB knows about,
        // including ones with no scanned ROMs. Hide the empties.
        .where((p) => p.romCount > 0)
        .toList();
  }

  /// Returns the current user's RetroAchievements progression as a map of
  /// RA game id → earned achievement count (`num_awarded`).
  ///
  /// RomM exposes per-user RA progress on the user (`GET /api/users/me` →
  /// `ra_progression.results`, each keyed by `rom_ra_id`), not on individual
  /// ROMs. Returns an empty map when the user hasn't linked/synced RA.
  Future<Map<int, int>> getRaProgression() async {
    final resp = await _authedGet('/api/users/me');
    return parseRaProgression(resp.body);
  }

  /// Parses `/api/users/me` JSON into a map of RA game id → earned count.
  /// Extracted for testability; tolerates missing/partial progression data.
  static Map<int, int> parseRaProgression(String body) {
    final result = <int, int>{};
    final decoded = jsonDecode(body);
    if (decoded is! Map) return result;
    final progression = decoded['ra_progression'];
    if (progression is! Map) return result;
    final results = progression['results'];
    if (results is! List) return result;
    for (final entry in results) {
      if (entry is! Map) continue;
      final gameId = (entry['rom_ra_id'] as num?)?.toInt();
      final awarded = (entry['num_awarded'] as num?)?.toInt();
      if (gameId != null && awarded != null) {
        result[gameId] = awarded;
      }
    }
    return result;
  }

  /// Returns the user's collections (`GET /api/collections`). Tolerates both a
  /// bare list and a `{items: [...]}` envelope; an empty/`{}` body yields [].
  Future<List<RommCollection>> getCollections() async {
    final resp = await _authedGet('/api/collections');
    return _parseCollections(resp.body, isVirtual: false);
  }

  /// Returns RomM virtual collections of [type] (default `collection`, i.e. the
  /// auto-generated game-series groupings shown as "Collections" in RomM's UI).
  /// The endpoint requires the `type` query parameter.
  Future<List<RommCollection>> getVirtualCollections({
    String type = 'collection',
  }) async {
    final resp = await _authedGet(
      '/api/collections/virtual?type=${Uri.encodeQueryComponent(type)}',
    );
    return _parseCollections(resp.body, isVirtual: true);
  }

  static List<RommCollection> _parseCollections(
    String body, {
    required bool isVirtual,
  }) {
    return _itemsOf(jsonDecode(body))
        .whereType<Map<String, dynamic>>()
        .map((j) => RommCollection.fromJson(j, isVirtual: isVirtual))
        .toList();
  }

  /// Returns one page of ROMs filtered by exactly one of [platformId],
  /// [collectionId] (user collection) or [virtualCollectionId] (RomM virtual
  /// collection). RomM paginates via `limit`/`offset`; [search] filters by name
  /// server-side.
  ///
  /// Thin wrapper over [getRomsPage] for callers that only want the rows.
  Future<List<RommRom>> getRoms({
    int? platformId,
    int? collectionId,
    String? virtualCollectionId,
    String? search,
    int limit = 50,
    int offset = 0,
  }) async {
    final page = await getRomsPage(
      platformIds: platformId == null ? const [] : [platformId],
      collectionId: collectionId,
      virtualCollectionId: virtualCollectionId,
      search: search,
      limit: limit,
      offset: offset,
    );
    return page.items;
  }

  /// Returns the ROMs this user has played, most recent first.
  ///
  /// Ordering by `last_played` is also a *filter*: RomM leaves ROMs that have
  /// never been played out of the result entirely, so this returns a short
  /// candidate list rather than a page of the library. Measured against RomM
  /// 5.1.0 on a 9,899-ROM library, where it answered with 5.
  ///
  /// That is what makes the connect-time playtime pull affordable — one request
  /// names every ROM worth asking about, instead of a session lookup per linked
  /// game. `order_dir` must be passed explicitly: RomM defaults to ascending,
  /// which would return the *least* recently played.
  Future<List<RommRom>> getRecentlyPlayedRoms({int limit = 25}) async {
    final resp = await _authedGetUri(
      Uri.parse('$_baseUrl/api/roms').replace(
        queryParameters: <String, String>{
          'limit': '$limit',
          'offset': '0',
          'order_by': 'last_played',
          'order_dir': 'desc',
        },
      ),
    );
    return _itemsOf(
      jsonDecode(resp.body),
    ).whereType<Map<String, dynamic>>().map(RommRom.fromJson).toList();
  }

  /// Returns one page of ROMs along with RomM's result [RommRomPage.total] and
  /// the filter values still available for the query.
  ///
  /// [genres] and [companies] are matched server-side across the whole library,
  /// so they narrow far more than post-filtering a fetched page can. Multiple
  /// values are OR-ed via RomM's `*_logic=any` default.
  ///
  /// Matching is exact and case-sensitive against RomM's own vocabulary:
  /// `Adventure` matches, `adventure` and `Advent` match nothing, and
  /// `Capcom` does not match a ROM credited to "Capcom Production Studio 1".
  /// Callers must therefore pass values RomM actually publishes — see the
  /// `filter_values` on [RommRomPage] — rather than values derived from a
  /// local library, which will silently return nothing when the two
  /// vocabularies disagree.
  ///
  /// Note RomM has no release-year filter — year has to stay a client-side
  /// concern.
  Future<RommRomPage> getRomsPage({
    List<int> platformIds = const [],
    int? collectionId,
    String? virtualCollectionId,
    String? search,
    List<String> genres = const [],
    List<String> companies = const [],
    int limit = 50,
    int offset = 0,
  }) async {
    // Repeated keys (platform_ids, genres, companies) need a list-valued map,
    // which Uri's queryParameters accepts as List<String>.
    final params = <String, dynamic>{
      'limit': '$limit',
      'offset': '$offset',
      'order_by': 'name',
    };
    if (platformIds.isNotEmpty) {
      // RomM filters by the plural `platform_ids`; `platform_id` is ignored.
      params['platform_ids'] = platformIds.map((id) => '$id').toList();
    }
    if (collectionId != null) {
      params['collection_id'] = '$collectionId';
    }
    if (virtualCollectionId != null) {
      params['virtual_collection_id'] = virtualCollectionId;
    }
    if (search != null && search.trim().isNotEmpty) {
      params['search_term'] = search.trim();
    }
    if (genres.isNotEmpty) params['genres'] = genres;
    if (companies.isNotEmpty) params['companies'] = companies;

    final resp = await _authedGetUri(
      Uri.parse('$_baseUrl/api/roms').replace(queryParameters: params),
    );
    final decoded = jsonDecode(resp.body);
    // RomM may return either a bare list or a paginated `{items: [...]}` object.
    final items = _itemsOf(
      decoded,
    ).whereType<Map<String, dynamic>>().map(RommRom.fromJson).toList();

    if (decoded is! Map<String, dynamic>) {
      return RommRomPage(items: items, total: items.length);
    }
    return RommRomPage(
      items: items,
      total: (decoded['total'] as num?)?.toInt() ?? items.length,
      filterValues: _filterValuesOf(decoded['filter_values']),
    );
  }

  /// Normalizes RomM's `filter_values` object into string lists.
  ///
  /// `platforms` is dropped: it holds platform *ids*, not names, so it has no
  /// place alongside the string-valued dimensions.
  static Map<String, List<String>> _filterValuesOf(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, List<String>>{};
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      if (key == 'platforms') continue;
      final value = entry.value;
      if (value is! List) continue;
      final values = [
        for (final v in value)
          if ((v?.toString() ?? '').trim().isNotEmpty) v.toString().trim(),
      ];
      if (values.isNotEmpty) out[key] = values;
    }
    return out;
  }

  /// Returns full detail for a single ROM.
  Future<RommRom> getRom(int id) async {
    final resp = await _authedGet('/api/roms/$id');
    return RommRom.fromJson(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Returns the raw ROM-detail JSON (metadata + media paths), or null on error.
  /// Used by the metadata import, which needs fields beyond [RommRom].
  Future<Map<String, dynamic>?> getRomDetail(int id) async {
    try {
      final resp = await _authedGet('/api/roms/$id');
      final decoded = jsonDecode(resp.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (e) {
      _log.e('RomM getRomDetail failed: $e');
      return null;
    }
  }

  /// Fetches raw image bytes (RomM-relative path or absolute URL), or null.
  /// The caller picks the on-disk extension from the actual content — RomM
  /// serves JPEG even from `*.png` cover paths, and the app's image lookup is
  /// extension-sensitive.
  ///
  /// With [requireImage] (the default) a body that isn't a recognisable image
  /// counts as a miss: a resource path RomM no longer has a file for falls
  /// through to its SPA shell, which answers **200 with HTML**. Writing that
  /// out would leave an undecodable `.png` behind — art that looks downloaded
  /// but renders as nothing — and would hide the miss from any caller trying a
  /// second source. Video fetches pass `requireImage: false`.
  Future<Uint8List?> fetchImageBytes(
    String pathOrUrl, {
    bool requireImage = true,
  }) async {
    try {
      final url = pathOrUrl.startsWith('http')
          ? pathOrUrl
          : '$_baseUrl${pathOrUrl.startsWith('/') ? '' : '/'}$pathOrUrl';
      final resp = await _httpClient
          .get(Uri.parse(url), headers: imageHeadersFor(url))
          .timeout(const Duration(seconds: 30));
      if (resp.statusCode != 200) {
        _log.w('RomM image fetch: HTTP ${resp.statusCode} for $url');
        return null;
      }
      final bytes = resp.bodyBytes;
      if (requireImage && !looksLikeImage(bytes)) {
        _log.w('RomM image fetch: non-image body for $url');
        return null;
      }
      return bytes;
    } catch (e) {
      _log.e('RomM image fetch failed: $e');
      return null;
    }
  }

  /// Whether [bytes] start with the magic numbers of an image format the app
  /// can decode. Deliberately content-based: RomM names every stored cover
  /// `big.png` whatever the source served, so the extension proves nothing.
  static bool looksLikeImage(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return true; // JPEG
    }
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true; // PNG
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true; // WEBP
    }
    if (bytes.length >= 6 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return true; // GIF
    }
    if (bytes.length >= 2 && bytes[0] == 0x42 && bytes[1] == 0x4D) {
      return true; // BMP
    }
    return false;
  }

  /// Returns the image file extension ('jpg'/'png'/'webp') implied by [bytes]'
  /// magic numbers, defaulting to 'png'.
  static String imageExtensionFor(Uint8List bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 12 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    return 'png';
  }

  /// Builds an absolute, authenticated-fetchable cover URL for [rom], or null.
  String? coverUrl(RommRom rom) => coverUrlCandidates(rom).firstOrNull;

  /// Every cover URL [rom] could be drawn from, best first: the metadata
  /// provider's own copy, then RomM's cached large and small files.
  ///
  /// RomM populates these independently — a ROM matched without a provider
  /// cover still has the cached file, and a library RomM never cached covers
  /// for only has the provider URL. Anything that draws a cover should walk the
  /// list rather than give up on the first entry, or a ROM whose art the server
  /// plainly has renders as a blank card.
  List<String> coverUrlCandidates(RommRom rom) {
    final urls = <String>[];
    for (final cover in [
      rom.urlCover,
      rom.pathCoverLarge,
      rom.pathCoverSmall,
    ]) {
      if (cover == null || cover.isEmpty) continue;
      urls.add(
        (cover.startsWith('http://') || cover.startsWith('https://'))
            ? cover
            : '$_baseUrl${cover.startsWith('/') ? '' : '/'}$cover',
      );
    }
    return urls;
  }

  /// Absolute, authenticated-fetchable cover URLs making up [collection]'s
  /// mosaic thumbnail (up to [limit], RomM's web UI uses 4). Empty when the
  /// server reported no covers.
  List<String> collectionCovers(RommCollection collection, {int limit = 4}) {
    return collection.coverUrls
        .map((c) {
          if (c.startsWith('http://') || c.startsWith('https://')) return c;
          return '$_baseUrl${c.startsWith('/') ? '' : '/'}$c';
        })
        .take(limit)
        .toList();
  }

  /// Absolute logo URL for [platform] (usually a public IGDB CDN URL), or null.
  String? platformLogoUrl(RommPlatform platform) {
    final logo = platform.urlLogo;
    if (logo == null || logo.isEmpty) return null;
    if (logo.startsWith('http://') || logo.startsWith('https://')) {
      return logo;
    }
    return '$_baseUrl${logo.startsWith('/') ? '' : '/'}$logo';
  }

  /// Auth headers for fetching an image, but only when [url] points at the RomM
  /// server itself — never leak the bearer token to third-party CDNs (IGDB,
  /// RetroAchievements, etc. host many covers/logos).
  Map<String, String> imageHeadersFor(String url) =>
      (_accessToken != null && url.startsWith(_baseUrl))
      ? _authHeaders
      : const {};

  /// URL of RomM's bundled SVG icon for [platform]. RomM only ships icons for
  /// some slugs, so this may 404.
  String platformIconUrl(RommPlatform platform) =>
      '$_baseUrl/assets/platforms/${platform.slug}.svg';

  /// Fetches an SVG document, returning its source if it looks like SVG, else
  /// null (e.g. a 404 for a slug RomM has no icon for).
  ///
  /// RomM's icons are Illustrator exports that style shapes via `<style>` CSS
  /// classes, which flutter_svg ignores (everything would render solid black),
  /// so we inline those class styles as presentation attributes first.
  Future<String?> fetchSvg(String url) async {
    try {
      final resp = await _httpClient
          .get(Uri.parse(url), headers: imageHeadersFor(url))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200 && resp.body.contains('<svg')) {
        return _inlineSvgClassStyles(resp.body);
      }
    } catch (_) {
      // Network/parse failure: fall through to null so the UI uses a fallback.
    }
    return null;
  }

  /// Converts `<style>`-block class rules into inline presentation attributes so
  /// renderers without CSS support draw the intended fills/strokes. Handles
  /// multi-selector rules and elements carrying several classes.
  static String _inlineSvgClassStyles(String svg) {
    final styleMatch = RegExp(
      r'<style[^>]*>(.*?)</style>',
      dotAll: true,
    ).firstMatch(svg);
    if (styleMatch == null) return svg;

    final classProps = <String, Map<String, String>>{};
    final ruleRe = RegExp(r'([^{}]+)\{([^{}]+)\}');
    for (final rule in ruleRe.allMatches(styleMatch.group(1)!)) {
      final props = <String, String>{};
      for (final decl in rule.group(2)!.split(';')) {
        final i = decl.indexOf(':');
        if (i < 0) continue;
        final key = decl.substring(0, i).trim();
        final value = decl.substring(i + 1).trim();
        if (key.isNotEmpty && value.isNotEmpty) props[key] = value;
      }
      if (props.isEmpty) continue;
      for (final sel in rule.group(1)!.split(',')) {
        final s = sel.trim();
        if (!s.startsWith('.')) continue;
        classProps.putIfAbsent(s.substring(1), () => {}).addAll(props);
      }
    }
    if (classProps.isEmpty) return svg;

    return svg.replaceAllMapped(RegExp(r'class="([^"]+)"'), (m) {
      final merged = <String, String>{};
      for (final c in m.group(1)!.trim().split(RegExp(r'\s+'))) {
        final p = classProps[c];
        if (p != null) merged.addAll(p);
      }
      if (merged.isEmpty) return m.group(0)!;
      final attrs = merged.entries
          .map((e) => '${e.key}="${e.value}"')
          .join(' ');
      return '${m.group(0)} $attrs';
    });
  }

  // ── Download ─────────────────────────────────────────────────────────────

  /// Streams a ROM download to [destFilePath].
  ///
  /// Writes to a sibling `.part` temp file and renames it into place only on
  /// success, so partial/cancelled downloads never leave a usable-looking file.
  /// Streaming (not buffering) keeps memory flat for multi-GB ROMs.
  ///
  /// [onProgress] receives `(receivedBytes, totalBytes?)`. [shouldCancel] is
  /// polled between chunks; returning true aborts and cleans up the temp file.
  Future<void> downloadRom(
    RommRom rom, {
    required String destFilePath,
    void Function(int received, int? total)? onProgress,
    bool Function()? shouldCancel,
  }) async {
    final fileName = rom.fsName.isNotEmpty ? rom.fsName : '${rom.id}';
    final endpoint =
        '/api/roms/${rom.id}/content/${Uri.encodeComponent(fileName)}';

    final tmpPath = '$destFilePath.part';
    final tmpFile = File(tmpPath);
    if (await tmpFile.exists()) {
      await tmpFile.delete();
    }
    await Directory(path.dirname(destFilePath)).create(recursive: true);

    // Build a fresh request each attempt so the shared retry policy (401 →
    // refresh, 403 → re-auth) picks up the new token on its second try.
    final resp = await _sendWithAuthRetry<http.StreamedResponse>(
      () => _httpClient.send(
        http.Request('GET', _uri(endpoint))..headers.addAll(_authHeaders),
      ),
      statusOf: (r) => r.statusCode,
    );

    if (resp.statusCode != 200) {
      throw RommException(
        'Download failed (${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }

    final total = resp.contentLength;
    var received = 0;
    final sink = tmpFile.openWrite();
    try {
      await for (final chunk in resp.stream) {
        if (shouldCancel?.call() ?? false) {
          await sink.close();
          await tmpFile.delete();
          throw RommCancelledException();
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
    } catch (e) {
      try {
        await sink.close();
      } catch (_) {}
      if (await tmpFile.exists()) {
        await tmpFile.delete();
      }
      if (e is RommException) rethrow;
      throw RommException('Download error: $e');
    }

    // Replace any existing destination, then move temp into place.
    final destFile = File(destFilePath);
    if (await destFile.exists()) {
      await destFile.delete();
    }
    await tmpFile.rename(destFilePath);
    _log.i('RomM download complete: $destFilePath ($received bytes)');
  }

  // ── Saves & states (asset sync) ──────────────────────────────────────────

  /// Lists the save files RomM holds for [romId] (`GET /api/saves?rom_id=`).
  Future<List<RommAsset>> listSaves({required int romId}) =>
      _listAssets('/api/saves', romId: romId, isState: false);

  /// Lists the save states RomM holds for [romId] (`GET /api/states?rom_id=`).
  Future<List<RommAsset>> listStates({required int romId}) =>
      _listAssets('/api/states', romId: romId, isState: true);

  Future<List<RommAsset>> _listAssets(
    String basePath, {
    required int romId,
    required bool isState,
  }) async {
    final resp = await _authedGet('$basePath?rom_id=$romId');
    return _itemsOf(jsonDecode(resp.body))
        .whereType<Map<String, dynamic>>()
        .map((j) => RommAsset.fromJson(j, isState: isState))
        .toList();
  }

  /// Downloads a save's bytes via the saves-only convenience route
  /// (`GET /api/saves/{id}/content`). Used by the generic [ISyncProvider] API
  /// which only has the asset id. For per-game sync prefer [downloadAssetByPath]
  /// (works for states too).
  Future<Uint8List> downloadSaveContent(int assetId) async {
    final resp = await _authedGet('/api/saves/$assetId/content');
    return resp.bodyBytes;
  }

  /// Downloads an asset's bytes from its server-relative [downloadPath]
  /// (`/api/raw/assets/{file_path}/{file_name}?timestamp=...`). This is the
  /// canonical route for BOTH saves and states — states have no `/content`
  /// endpoint.
  Future<Uint8List> downloadAssetByPath(String downloadPath) async {
    // Asset content can be large, so allow a longer per-attempt timeout than a
    // plain metadata GET.
    final resp = await _authedGetUri(
      _assetUri(downloadPath),
      timeout: const Duration(seconds: 60),
    );
    return resp.bodyBytes;
  }

  /// Builds the request URI for a server-supplied asset [downloadPath].
  ///
  /// RomM emits this path **un-encoded** — raw file names and a raw timestamp
  /// — so it must be percent-encoded before use. [Uri.encodeFull] is wrong
  /// here: it leaves `#`/`?`/`&` intact (a save named `Zelda #1.srm` would lose
  /// its `#…` tail to a URL fragment → 404) and would double-escape any literal
  /// `%`. Instead the scheme/host is preserved verbatim while each path segment
  /// and query key/value is encoded individually, so plain-ASCII names come out
  /// byte-identical to the un-encoded input.
  Uri _assetUri(String downloadPath) {
    final String origin;
    final String rest; // path[?query], server-relative, still un-encoded
    if (downloadPath.startsWith('http')) {
      // Absolute URL: peel off scheme://authority (no raw specials live there),
      // keeping the raw path+query for manual encoding below.
      final slash = downloadPath.indexOf('/', downloadPath.indexOf('://') + 3);
      origin = slash == -1 ? downloadPath : downloadPath.substring(0, slash);
      rest = slash == -1 ? '' : downloadPath.substring(slash);
    } else {
      origin = _baseUrl;
      rest = downloadPath.startsWith('/') ? downloadPath : '/$downloadPath';
    }

    final q = rest.indexOf('?');
    final rawPath = q == -1 ? rest : rest.substring(0, q);
    final rawQuery = q == -1 ? null : rest.substring(q + 1);

    final encodedPath = rawPath.split('/').map(Uri.encodeComponent).join('/');
    final encodedQuery = rawQuery == null
        ? ''
        : '?${rawQuery.split('&').map((pair) {
            final eq = pair.indexOf('=');
            if (eq == -1) return Uri.encodeQueryComponent(pair);
            final k = Uri.encodeQueryComponent(pair.substring(0, eq));
            final v = Uri.encodeQueryComponent(pair.substring(eq + 1));
            return '$k=$v';
          }).join('&')}';

    return Uri.parse('$origin$encodedPath$encodedQuery');
  }

  /// Uploads [file] as a save for [romId] (`POST /api/saves`, field `saveFile`).
  ///
  /// [slot] is a stable *name* (RomM's own example is `autosave`), not a number.
  /// Passing one opts the save into RomM's `(rom_id, slot)` pairing — and into
  /// server-side renaming, since RomM datetime-tags every slotted upload.
  Future<RommAsset> uploadSave(
    int romId,
    File file, {
    String? emulator,
    String? slot,
    String? deviceId,
    bool overwrite = true,
  }) => _uploadAsset(
    '/api/saves',
    fileField: 'saveFile',
    romId: romId,
    file: file,
    emulator: emulator,
    slot: slot,
    deviceId: deviceId,
    overwrite: overwrite,
    isState: false,
  );

  /// Uploads [file] as a save state for [romId] (`POST /api/states`, field
  /// `stateFile`).
  ///
  /// [slot] is accepted for symmetry with [uploadSave] only — `/api/states` has
  /// no slot parameter, so RomM ignores it and never tags a state's filename.
  Future<RommAsset> uploadState(
    int romId,
    File file, {
    String? emulator,
    String? slot,
    String? deviceId,
    bool overwrite = true,
  }) => _uploadAsset(
    '/api/states',
    fileField: 'stateFile',
    romId: romId,
    file: file,
    emulator: emulator,
    slot: slot,
    deviceId: deviceId,
    overwrite: overwrite,
    isState: true,
  );

  /// Replaces the contents of the existing save asset [assetId]
  /// (`PUT /api/saves/{id}`, field `saveFile`).
  Future<RommAsset> updateSave(int assetId, File file) => _updateAsset(
    '/api/saves',
    fileField: 'saveFile',
    assetId: assetId,
    file: file,
    isState: false,
  );

  /// Replaces the contents of the existing state asset [assetId]
  /// (`PUT /api/states/{id}`, field `stateFile`).
  Future<RommAsset> updateState(int assetId, File file) => _updateAsset(
    '/api/states',
    fileField: 'stateFile',
    assetId: assetId,
    file: file,
    isState: true,
  );

  /// Updates an existing asset in place.
  ///
  /// This is deliberately not a `POST` with `overwrite=true`. RomM identifies an
  /// asset by `(rom_id, file_name)` and *ignores* `emulator` when matching, but
  /// it stores the file under the emulator label as a directory component. A
  /// `POST` from a device whose label differs from the one the asset was
  /// created with therefore updates the row's size and timestamp, writes its
  /// bytes to a different directory, and leaves `file_path` pointing at the
  /// original — so the download endpoint keeps serving the *old* file forever
  /// while the metadata describes the new one. Verified against RomM 5.1.0.
  ///
  /// `PUT` carries no emulator at all and rewrites the file at the path the
  /// asset already has, which keeps content and metadata in agreement.
  Future<RommAsset> _updateAsset(
    String basePath, {
    required String fileField,
    required int assetId,
    required File file,
    required bool isState,
  }) async {
    final uri = Uri.parse('$_baseUrl$basePath/$assetId');

    Future<http.StreamedResponse> send() async {
      final req = http.MultipartRequest('PUT', uri)
        ..headers.addAll(_authHeaders)
        ..files.add(
          await http.MultipartFile.fromPath(
            fileField,
            file.path,
            filename: path.basename(file.path),
          ),
        );
      return _httpClient.send(req);
    }

    final resp = await _sendWithAuthRetry<http.StreamedResponse>(
      send,
      statusOf: (r) => r.statusCode,
    );

    final body = await resp.stream.bytesToString();
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw RommException(
        'Update failed (${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }
    return RommAsset.fromJson(
      jsonDecode(body) as Map<String, dynamic>,
      isState: isState,
    );
  }

  Future<RommAsset> _uploadAsset(
    String basePath, {
    required String fileField,
    required int romId,
    required File file,
    String? emulator,
    String? slot,
    String? deviceId,
    required bool overwrite,
    required bool isState,
  }) async {
    final params = <String, String>{
      'rom_id': '$romId',
      'overwrite': '$overwrite',
    };
    if (emulator != null && emulator.isNotEmpty) params['emulator'] = emulator;
    if (slot != null && slot.isNotEmpty) params['slot'] = slot;
    if (deviceId != null && deviceId.isNotEmpty) params['device_id'] = deviceId;
    final uri = Uri.parse(
      '$_baseUrl$basePath',
    ).replace(queryParameters: params);

    Future<http.StreamedResponse> send() async {
      final req = http.MultipartRequest('POST', uri)
        ..headers.addAll(_authHeaders)
        ..files.add(
          await http.MultipartFile.fromPath(
            fileField,
            file.path,
            filename: path.basename(file.path),
          ),
        );
      return _httpClient.send(req);
    }

    // Shared retry policy: 401 → refresh, 403 → re-auth (cached token may
    // predate the assets.write scope).
    final resp = await _sendWithAuthRetry<http.StreamedResponse>(
      send,
      statusOf: (r) => r.statusCode,
    );

    final body = await resp.stream.bytesToString();
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw RommException(
        'Upload failed (${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }
    final decoded = jsonDecode(body);
    return RommAsset.fromJson(
      decoded as Map<String, dynamic>,
      isState: isState,
    );
  }

  // ── Play sessions (playtime sync) ─────────────────────────────────────────

  /// Uploads finished play sessions (`POST /api/play-sessions`).
  ///
  /// RomM caps a batch at 100 and dedupes on `(rom_id, start_time)`, so a
  /// re-push of a session it already holds is reported back as `duplicate`
  /// rather than added twice. Ingesting also moves the ROM's `last_played`
  /// forward server-side, which is why there's no separate props call.
  ///
  /// Throws [RommException]; a 404 (server predates the feature) or a 403 that
  /// survives the shared re-auth retry also disables further attempts for this
  /// connection — see [playtimeSyncAvailable].
  Future<RommPlaySessionIngestResult> ingestPlaySessions(
    List<RommPlaySession> sessions,
  ) async {
    if (sessions.isEmpty) {
      return const RommPlaySessionIngestResult(
        acceptedIndexes: {},
        rejectedIndexes: {},
        createdCount: 0,
        skippedCount: 0,
      );
    }
    if (sessions.length > maxPlaySessionBatch) {
      throw RommException(
        'Play-session batch exceeds RomM\'s limit of $maxPlaySessionBatch',
      );
    }

    final body = jsonEncode({
      'sessions': [for (final s in sessions) s.toIngestJson()],
    });

    final resp = await _sendWithAuthRetry<http.Response>(
      () => _httpClient
          .post(
            _uri('/api/play-sessions'),
            headers: {..._authHeaders, 'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 30)),
      statusOf: (r) => r.statusCode,
    );

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      _notePlaySessionFailure(resp.statusCode);
      throw RommException(
        'Play-session upload failed (${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is! Map<String, dynamic>) {
      throw RommException('Unexpected play-session response');
    }
    return RommPlaySessionIngestResult.fromJson(decoded);
  }

  /// Every play session the current user has for [romId], across all devices
  /// (`GET /api/play-sessions?rom_id=`).
  ///
  /// RomM only applies its default 50-row page cap when no time filter is
  /// given, so an epoch `start_after` is passed to get the complete history —
  /// the aggregate is meaningless if it silently stops at the newest 50.
  Future<List<RommPlaySession>> getPlaySessions({required int romId}) async {
    final uri = Uri.parse('$_baseUrl/api/play-sessions').replace(
      queryParameters: {
        'rom_id': '$romId',
        'start_after': '1970-01-01T00:00:00Z',
      },
    );

    final http.Response resp;
    try {
      resp = await _authedGetUri(uri);
    } on RommException catch (e) {
      if (e.statusCode != null) _notePlaySessionFailure(e.statusCode!);
      rethrow;
    }

    return _itemsOf(
      jsonDecode(resp.body),
    ).whereType<Map<String, dynamic>>().map(RommPlaySession.fromJson).toList();
  }

  /// Marks the play-session API unusable when the server's answer says it will
  /// never work on this connection: `404` (endpoint absent) or a `403` that has
  /// already survived one re-authentication, i.e. a genuine scope denial.
  void _notePlaySessionFailure(int statusCode) {
    if (statusCode == 404 || statusCode == 403) {
      if (_playSessionsSupported) {
        _log.w(
          'RomM play-session API unavailable ($statusCode) — '
          'playtime sync disabled for this connection',
        );
      }
      _playSessionsSupported = false;
    }
  }
}
