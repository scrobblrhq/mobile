/// Dart mirrors of the API-facing Rust models (`crates/shared/src/models.rs`
/// and handler response types). Field names match the server's serde output
/// exactly.
library;

DateTime _date(Object? v) => DateTime.parse(v as String).toUtc();
int _int(Object? v) => (v as num).toInt();
int? _intOrNull(Object? v) => v == null ? null : (v as num).toInt();

/// `AuthResponse` from POST /v1/auth/login and /v1/auth/register.
class AuthResponse {
  const AuthResponse({
    required this.token,
    required this.userId,
    required this.username,
  });

  final String token;
  final int userId;
  final String username;

  factory AuthResponse.fromJson(Map<String, dynamic> json) => AuthResponse(
    token: json['token'] as String,
    userId: _int(json['user_id']),
    username: json['username'] as String,
  );
}

/// `CreateTokenResponse` from POST /v1/auth/tokens. The raw token is shown
/// exactly once — it is stored in secure storage immediately.
class CreatedApiToken {
  const CreatedApiToken({
    required this.id,
    required this.name,
    required this.token,
    required this.scopes,
  });

  final String id;
  final String name;
  final String token;
  final List<String> scopes;

  factory CreatedApiToken.fromJson(Map<String, dynamic> json) =>
      CreatedApiToken(
        id: json['id'] as String,
        name: json['name'] as String,
        token: json['token'] as String,
        scopes: [
          for (final s in json['scopes'] as List<dynamic>? ?? []) s as String,
        ],
      );
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.username,
    this.displayName,
    this.bio,
    this.imageUrl,
    required this.scrobbleCount,
    required this.isPrivate,
    this.isFollowing,
  });

  final int id;
  final String username;
  final String? displayName;
  final String? bio;
  final String? imageUrl;
  final int scrobbleCount;
  final bool isPrivate;

  /// Whether the authenticated viewer follows this user; null when viewing
  /// anonymously or your own profile.
  final bool? isFollowing;

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: _int(json['id']),
    username: json['username'] as String,
    displayName: json['display_name'] as String?,
    bio: json['bio'] as String?,
    imageUrl: json['image_url'] as String?,
    scrobbleCount: _intOrNull(json['scrobble_count']) ?? 0,
    isPrivate: json['is_private'] == true,
    isFollowing: json['is_following'] as bool?,
  );
}

/// `FriendsResponse` — follower and following lists for a user.
class Friends {
  const Friends({required this.followers, required this.following});

  final List<UserProfile> followers;
  final List<UserProfile> following;

  factory Friends.fromJson(Map<String, dynamic> json) => Friends(
    followers: [
      for (final u in json['followers'] as List<dynamic>? ?? [])
        UserProfile.fromJson(u as Map<String, dynamic>),
    ],
    following: [
      for (final u in json['following'] as List<dynamic>? ?? [])
        UserProfile.fromJson(u as Map<String, dynamic>),
    ],
  );
}

/// `ScrobbleRich` — a scrobble joined with track/artist/album metadata,
/// including the enrichment pipeline's `album_image`.
class ScrobbleRich {
  const ScrobbleRich({
    required this.id,
    required this.playedAt,
    required this.source,
    required this.trackId,
    required this.trackTitle,
    required this.artistId,
    required this.artistName,
    this.albumId,
    this.albumTitle,
    this.albumImage,
    this.durationMs,
  });

  final int id;
  final DateTime playedAt;
  final String source;
  final int trackId;
  final String trackTitle;
  final int artistId;
  final String artistName;
  final int? albumId;
  final String? albumTitle;
  final String? albumImage;
  final int? durationMs;

  factory ScrobbleRich.fromJson(Map<String, dynamic> json) => ScrobbleRich(
    id: _int(json['id']),
    playedAt: _date(json['played_at']),
    source: json['source'] as String? ?? '',
    trackId: _int(json['track_id']),
    trackTitle: json['track_title'] as String,
    artistId: _int(json['artist_id']),
    artistName: json['artist_name'] as String,
    albumId: _intOrNull(json['album_id']),
    albumTitle: json['album_title'] as String?,
    albumImage: json['album_image'] as String?,
    durationMs: _intOrNull(json['duration_ms']),
  );
}

/// `NowPlayingRich` — pushed over the `/live` SSE stream.
class NowPlayingRich {
  const NowPlayingRich({
    required this.trackTitle,
    required this.artistName,
    this.albumTitle,
    this.albumImage,
    this.artistImage,
    required this.startedAt,
    required this.expiresAt,
    required this.source,
  });

  final String trackTitle;
  final String artistName;
  final String? albumTitle;
  final String? albumImage;
  final String? artistImage;
  final DateTime startedAt;
  final DateTime expiresAt;
  final String source;

  /// Best available artwork: tracks have no image of their own, so the
  /// album cover is the track's artwork, then the artist image, then the
  /// caller's placeholder (null).
  String? get artworkUrl => albumImage ?? artistImage;

  factory NowPlayingRich.fromJson(Map<String, dynamic> json) => NowPlayingRich(
    trackTitle: json['track_title'] as String,
    artistName: json['artist_name'] as String,
    albumTitle: json['album_title'] as String?,
    albumImage: json['album_image'] as String?,
    artistImage: json['artist_image'] as String?,
    startedAt: _date(json['started_at']),
    expiresAt: _date(json['expires_at']),
    source: json['source'] as String? ?? '',
  );
}

/// `TopListener` — a user who listens to an artist or track, with count.
class TopListener {
  const TopListener({
    required this.userId,
    required this.username,
    this.displayName,
    this.imageUrl,
    required this.playCount,
  });

  final int userId;
  final String username;
  final String? displayName;
  final String? imageUrl;
  final int playCount;

  factory TopListener.fromJson(Map<String, dynamic> json) => TopListener(
    userId: _int(json['user_id']),
    username: json['username'] as String,
    displayName: json['display_name'] as String?,
    imageUrl: json['image_url'] as String?,
    playCount: _int(json['play_count']),
  );
}

/// `SearchResponse` — artists, tracks and users matching a query.
class SearchResults {
  const SearchResults({
    required this.artists,
    required this.tracks,
    required this.users,
  });

  final List<Artist> artists;
  final List<Track> tracks;
  final List<UserProfile> users;

  bool get isEmpty => artists.isEmpty && tracks.isEmpty && users.isEmpty;

  factory SearchResults.fromJson(Map<String, dynamic> json) => SearchResults(
    artists: [
      for (final a in json['artists'] as List<dynamic>? ?? [])
        Artist.fromJson(a as Map<String, dynamic>),
    ],
    tracks: [
      for (final t in json['tracks'] as List<dynamic>? ?? [])
        Track.fromJson(t as Map<String, dynamic>),
    ],
    users: [
      for (final u in json['users'] as List<dynamic>? ?? [])
        UserProfile.fromJson(u as Map<String, dynamic>),
    ],
  );
}

class TopArtist {
  const TopArtist({
    required this.artistId,
    required this.artistName,
    this.imageUrl,
    required this.playCount,
  });

  final int artistId;
  final String artistName;
  final String? imageUrl;
  final int playCount;

  factory TopArtist.fromJson(Map<String, dynamic> json) => TopArtist(
    artistId: _int(json['artist_id']),
    artistName: json['artist_name'] as String,
    imageUrl: json['image_url'] as String?,
    playCount: _int(json['play_count']),
  );
}

class TopTrack {
  const TopTrack({
    required this.trackId,
    required this.trackTitle,
    required this.artistId,
    required this.artistName,
    this.albumImage,
    required this.playCount,
  });

  final int trackId;
  final String trackTitle;
  final int artistId;
  final String artistName;
  final String? albumImage;
  final int playCount;

  factory TopTrack.fromJson(Map<String, dynamic> json) => TopTrack(
    trackId: _int(json['track_id']),
    trackTitle: json['track_title'] as String,
    artistId: _int(json['artist_id']),
    artistName: json['artist_name'] as String,
    albumImage: json['album_image'] as String?,
    playCount: _int(json['play_count']),
  );
}

/// `Artist` — catalog entity; `imageUrl`/`bio` are filled by the worker's
/// enrichment pipeline (Deezer images, Last.fm bios) and may lag behind the
/// first scrobble.
class Artist {
  const Artist({
    required this.id,
    required this.name,
    this.mbid,
    this.imageUrl,
    this.bio,
    required this.scrobbleCount,
    required this.listenerCount,
  });

  final int id;
  final String name;
  final String? mbid;
  final String? imageUrl;
  final String? bio;
  final int scrobbleCount;
  final int listenerCount;

  factory Artist.fromJson(Map<String, dynamic> json) => Artist(
    id: _int(json['id']),
    name: json['name'] as String,
    mbid: json['mbid'] as String?,
    imageUrl: json['image_url'] as String?,
    bio: json['bio'] as String?,
    scrobbleCount: _intOrNull(json['scrobble_count']) ?? 0,
    listenerCount: _intOrNull(json['listener_count']) ?? 0,
  );
}

class Track {
  const Track({
    required this.id,
    required this.artistId,
    this.albumId,
    required this.title,
    this.mbid,
    this.durationMs,
    required this.scrobbleCount,
  });

  final int id;
  final int artistId;
  final int? albumId;
  final String title;
  final String? mbid;
  final int? durationMs;
  final int scrobbleCount;

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: _int(json['id']),
    artistId: _int(json['artist_id']),
    albumId: _intOrNull(json['album_id']),
    title: json['title'] as String,
    mbid: json['mbid'] as String?,
    durationMs: _intOrNull(json['duration_ms']),
    scrobbleCount: _intOrNull(json['scrobble_count']) ?? 0,
  );
}

class ActivityDay {
  const ActivityDay({required this.day, required this.scrobbleCount});

  final DateTime day;
  final int scrobbleCount;

  factory ActivityDay.fromJson(Map<String, dynamic> json) => ActivityDay(
    day: _date(json['day']),
    scrobbleCount: _int(json['scrobble_count']),
  );
}

/// `ImageCandidate` — a community-uploaded artist/album image. The most-liked
/// candidate past the vote threshold becomes the entity's displayed image.
class ImageCandidate {
  const ImageCandidate({
    required this.id,
    required this.url,
    required this.uploadedBy,
    required this.voteCount,
    required this.hasVoted,
    required this.isDefault,
  });

  final int id;
  final String url;
  final String uploadedBy;
  final int voteCount;
  final bool hasVoted;
  final bool isDefault;

  factory ImageCandidate.fromJson(Map<String, dynamic> json) => ImageCandidate(
    id: _int(json['id']),
    url: json['url'] as String,
    uploadedBy: json['uploaded_by'] as String,
    voteCount: _int(json['vote_count']),
    hasVoted: json['has_voted'] == true,
    isDefault: json['is_default'] == true,
  );
}

/// `Comment` — a user comment on an artist or track, with commenter identity.
class Comment {
  const Comment({
    required this.id,
    required this.userId,
    required this.username,
    this.displayName,
    this.imageUrl,
    required this.body,
    required this.createdAt,
  });

  final int id;
  final int userId;
  final String username;
  final String? displayName;
  final String? imageUrl;
  final String body;
  final DateTime createdAt;

  factory Comment.fromJson(Map<String, dynamic> json) => Comment(
    id: _int(json['id']),
    userId: _int(json['user_id']),
    username: json['username'] as String,
    displayName: json['display_name'] as String?,
    imageUrl: json['image_url'] as String?,
    body: json['body'] as String,
    createdAt: _date(json['created_at']),
  );
}
