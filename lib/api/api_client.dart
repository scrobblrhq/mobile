/// HTTP client for the Scrobblr API.
///
/// One instance per credential: the UI uses a session-token client (the
/// `optional_auth` read routes only honor sessions), the background
/// scrobbler uses a long-lived API-token client (survives "logout all
/// devices").
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  bool get isAuthError => statusCode == 401;

  /// 4xx (except 429) means retrying the same payload can never succeed.
  bool get isPermanent =>
      statusCode >= 400 && statusCode < 500 && statusCode != 429;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class ScrobblrApi {
  ScrobblrApi({required String baseUrl, this.token, http.Client? client})
    : baseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), ''),
      _client = client ?? http.Client();

  final String baseUrl;
  final String? token;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  void close() => _client.close();

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    if (token != null) 'authorization': 'Bearer $token',
  };

  Never _fail(http.Response res) {
    String message = res.body;
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['message'] is String) {
        message = decoded['message'] as String;
      } else if (decoded is Map && decoded['error'] is String) {
        message = decoded['error'] as String;
      }
    } catch (_) {}
    throw ApiException(res.statusCode, message);
  }

  Future<dynamic> _get(String path, [Map<String, String>? query]) async {
    final res = await _client
        .get(_uri(path, query), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) _fail(res);
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<dynamic> _post(String path, [Object? body]) async {
    final res = await _client
        .post(
          _uri(path),
          headers: _headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) _fail(res);
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<void> _delete(String path) async {
    final res = await _client
        .delete(_uri(path), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) _fail(res);
  }

  Future<dynamic> _patch(String path, Object body) async {
    final res = await _client
        .patch(_uri(path), headers: _headers, body: jsonEncode(body))
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) _fail(res);
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<AuthResponse> login(String username, String password) async {
    final json = await _post('/v1/auth/login', {
      'username': username,
      'password': password,
    });
    return AuthResponse.fromJson(json as Map<String, dynamic>);
  }

  Future<AuthResponse> register({
    required String username,
    required String email,
    required String password,
    String? displayName,
  }) async {
    final json = await _post('/v1/auth/register', {
      'username': username,
      'email': email,
      'password': password,
      if (displayName != null && displayName.isNotEmpty)
        'display_name': displayName,
    });
    return AuthResponse.fromJson(json as Map<String, dynamic>);
  }

  Future<CreatedApiToken> createApiToken(
    String name, {
    List<String> scopes = const ['scrobble'],
  }) async {
    final json = await _post('/v1/auth/tokens', {
      'name': name,
      'scopes': scopes,
    });
    return CreatedApiToken.fromJson(json as Map<String, dynamic>);
  }

  Future<void> deleteApiToken(String id) => _delete('/v1/auth/tokens/$id');

  Future<void> logout() => _post('/v1/auth/logout');

  Future<UserProfile> me() async {
    final json = await _get('/v1/user/me');
    return UserProfile.fromJson(json as Map<String, dynamic>);
  }

  /// Public profile; includes `is_following` when authenticated. Throws
  /// ApiException(403) for private profiles.
  Future<UserProfile> userProfile(String username) async {
    final json = await _get('/v1/user/$username');
    return UserProfile.fromJson(json as Map<String, dynamic>);
  }

  /// Updates the signed-in user's profile. Omitted (null) fields stay
  /// unchanged server-side; empty strings clear the field.
  Future<UserProfile> updateProfile({
    String? displayName,
    String? bio,
    String? imageUrl,
    bool? isPrivate,
  }) async {
    final json = await _patch('/v1/user/me', {
      if (displayName != null) 'display_name': displayName,
      if (bio != null) 'bio': bio,
      if (imageUrl != null) 'image_url': imageUrl,
      if (isPrivate != null) 'is_private': isPrivate,
    });
    return UserProfile.fromJson(json as Map<String, dynamic>);
  }

  Future<Friends> friends(String username) async {
    final json = await _get('/v1/user/$username/friends');
    return Friends.fromJson(json as Map<String, dynamic>);
  }

  Future<void> followUser(String username) =>
      _post('/v1/user/$username/follow');

  Future<void> unfollowUser(String username) =>
      _delete('/v1/user/$username/follow');

  Future<void> submitScrobble({
    required String artist,
    required String track,
    String? album,
    required DateTime playedAt,
    int? durationMs,
    int? listenedMs,
    required String source,
  }) async {
    await _post('/v1/scrobble', {
      'artist': artist,
      'track': track,
      if (album != null) 'album': album,
      'played_at': playedAt.toUtc().toIso8601String(),
      if (durationMs != null) 'duration_ms': durationMs,
      if (listenedMs != null) 'listened_ms': listenedMs,
      'source': source,
    });
  }

  Future<void> updateNowPlaying({
    required String artist,
    required String track,
    String? album,
    int? durationMs,
    required String source,
  }) async {
    await _post('/v1/now-playing', {
      'artist': artist,
      'track': track,
      if (album != null) 'album': album,
      if (durationMs != null) 'duration_ms': durationMs,
      'source': source,
    });
  }

  Future<List<ScrobbleRich>> recentScrobbles(
    String username, {
    int limit = 50,
    DateTime? before,
  }) async {
    final json = await _get('/v1/user/$username/recent', {
      'limit': '$limit',
      if (before != null) 'before': before.toUtc().toIso8601String(),
    });
    return [
      for (final item in json as List<dynamic>)
        ScrobbleRich.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<List<TopArtist>> topArtists(
    String username, {
    String period = 'overall',
    int limit = 12,
  }) async {
    final json = await _get('/v1/user/$username/top-artists', {
      'period': period,
      'limit': '$limit',
    });
    return [
      for (final item in json as List<dynamic>)
        TopArtist.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<List<TopTrack>> topTracks(
    String username, {
    String period = 'overall',
    int limit = 20,
  }) async {
    final json = await _get('/v1/user/$username/top-tracks', {
      'period': period,
      'limit': '$limit',
    });
    return [
      for (final item in json as List<dynamic>)
        TopTrack.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<List<ActivityDay>> heatmap(String username) async {
    final json = await _get('/v1/user/$username/heatmap');
    return [
      for (final item in json as List<dynamic>)
        ActivityDay.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<Artist> artist(int id) async {
    final json = await _get('/v1/artist/$id');
    return Artist.fromJson(json as Map<String, dynamic>);
  }

  Future<Track> track(int id) async {
    final json = await _get('/v1/track/$id');
    return Track.fromJson(json as Map<String, dynamic>);
  }

  Future<List<TopTrack>> artistTopTracks(int id, {int limit = 10}) async {
    final json = await _get('/v1/artist/$id/top-tracks', {'limit': '$limit'});
    return [
      for (final t in json as List<dynamic>)
        TopTrack.fromJson(t as Map<String, dynamic>),
    ];
  }

  Future<List<TopListener>> artistListeners(int id, {int limit = 10}) async {
    final json = await _get('/v1/artist/$id/listeners', {'limit': '$limit'});
    return [
      for (final l in json as List<dynamic>)
        TopListener.fromJson(l as Map<String, dynamic>),
    ];
  }

  Future<List<TopListener>> trackListeners(int id, {int limit = 10}) async {
    final json = await _get('/v1/track/$id/listeners', {'limit': '$limit'});
    return [
      for (final l in json as List<dynamic>)
        TopListener.fromJson(l as Map<String, dynamic>),
    ];
  }

  Future<SearchResults> search(String query, {int limit = 10}) async {
    final json = await _get('/v1/search', {'q': query, 'limit': '$limit'});
    return SearchResults.fromJson(json as Map<String, dynamic>);
  }

  /// Queue a forced re-enrichment (worker pipeline) for a catalog entity.
  Future<void> refreshArtist(int id) => _post('/v1/artist/$id/refresh');
  Future<void> refreshTrack(int id) => _post('/v1/track/$id/refresh');
  Future<void> refreshAlbum(int id) => _post('/v1/album/$id/refresh');

  /// Uploads [bytes] as multipart `image` to [path], returning the decoded
  /// JSON body. Shared by avatar and artist/album artwork uploads.
  Future<dynamic> _uploadImage(String path, List<int> bytes) async {
    final req =
        http.MultipartRequest('POST', _uri(path))
          ..headers.addAll(_headers)
          ..files.add(
            http.MultipartFile.fromBytes('image', bytes, filename: 'image.jpg'),
          );
    // MultipartRequest sets its own multipart content-type + boundary.
    req.headers.remove('content-type');
    final streamed = await req.send().timeout(_timeout);
    final res = await http.Response.fromStream(streamed);
    if (res.statusCode < 200 || res.statusCode >= 300) _fail(res);
    return res.body.isEmpty ? null : jsonDecode(utf8.decode(res.bodyBytes));
  }

  Future<UserProfile> uploadAvatar(List<int> bytes) async {
    final json = await _uploadImage('/v1/user/me/avatar', bytes);
    return UserProfile.fromJson(json as Map<String, dynamic>);
  }

  List<ImageCandidate> _candidates(dynamic json) => [
    for (final c in json as List<dynamic>)
      ImageCandidate.fromJson(c as Map<String, dynamic>),
  ];

  /// Proposes a community image for an artist; returns the refreshed
  /// candidate list (the upload doesn't replace the image, it's voted on).
  Future<List<ImageCandidate>> uploadArtistImage(
    int id,
    List<int> bytes,
  ) async {
    return _candidates(await _uploadImage('/v1/artist/$id/image', bytes));
  }

  Future<List<ImageCandidate>> uploadAlbumImage(int id, List<int> bytes) async {
    return _candidates(await _uploadImage('/v1/album/$id/image', bytes));
  }

  Future<List<ImageCandidate>> artistImages(int id) async =>
      _candidates(await _get('/v1/artist/$id/images'));

  Future<List<ImageCandidate>> albumImages(int id) async =>
      _candidates(await _get('/v1/album/$id/images'));

  Future<List<ImageCandidate>> voteImage(int candidateId) async =>
      _candidates(await _post('/v1/image/$candidateId/vote'));

  Future<List<ImageCandidate>> unvoteImage(int candidateId) async {
    final res = await _client
        .delete(_uri('/v1/image/$candidateId/vote'), headers: _headers)
        .timeout(_timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) _fail(res);
    return _candidates(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  Future<List<Comment>> artistComments(int id) async {
    final json = await _get('/v1/artist/$id/comments');
    return [
      for (final c in json as List<dynamic>)
        Comment.fromJson(c as Map<String, dynamic>),
    ];
  }

  Future<List<Comment>> trackComments(int id) async {
    final json = await _get('/v1/track/$id/comments');
    return [
      for (final c in json as List<dynamic>)
        Comment.fromJson(c as Map<String, dynamic>),
    ];
  }

  Future<Comment> addArtistComment(int id, String body) async {
    final json = await _post('/v1/artist/$id/comments', {'body': body});
    return Comment.fromJson(json as Map<String, dynamic>);
  }

  Future<Comment> addTrackComment(int id, String body) async {
    final json = await _post('/v1/track/$id/comments', {'body': body});
    return Comment.fromJson(json as Map<String, dynamic>);
  }

  Future<void> deleteComment(int id) => _delete('/v1/comments/$id');

  /// Auto-reconnecting stream of the user's now-playing state. Emits the
  /// current state immediately on connect, `null` when playback stops.
  ///
  /// Cancellation is observed at yield points; the server's SSE keep-alives
  /// guarantee those happen regularly, after which the connection closes.
  Stream<NowPlayingRich?> liveNowPlaying(String username) async* {
    while (true) {
      final client = http.Client();
      try {
        final req = http.Request('GET', _uri('/v1/user/$username/live'));
        req.headers.addAll({..._headers, 'accept': 'text/event-stream'});
        final res = await client.send(req).timeout(_timeout);
        if (res.statusCode != 200) {
          throw ApiException(res.statusCode, 'SSE connect failed');
        }

        final lines = res.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter());

        var data = StringBuffer();
        await for (final line in lines) {
          if (line.isEmpty) {
            if (data.isNotEmpty) {
              final payload = data.toString();
              data = StringBuffer();
              final parsed = _parseNowPlayingEvent(payload);
              yield parsed;
            }
            continue;
          }
          if (line.startsWith(':')) continue; // keep-alive comment
          if (line.startsWith('data:')) {
            data.write(line.substring(5).trimLeft());
          }
        }
      } on Object {
        // Network drop / server restart: fall through and reconnect.
      } finally {
        client.close();
      }
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  NowPlayingRich? _parseNowPlayingEvent(String payload) {
    if (payload == 'null') return null;
    try {
      return NowPlayingRich.fromJson(
        jsonDecode(payload) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }
}
