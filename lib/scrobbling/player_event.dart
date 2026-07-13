/// Raw media event forwarded from the Android side.
///
/// This file is pure Dart (no Flutter imports) so the whole scrobbling
/// pipeline can be unit-tested without a device.
library;

/// Where the event was captured.
///
/// Today everything comes from `MediaSessionManager` (which the
/// notification-listener permission gates). `notification` is reserved for
/// future parsers that read notification text directly for players that
/// don't expose a media session.
enum PlayerEventOrigin { mediaSession, notification, sessionEnded }

class PlayerEvent {
  const PlayerEvent({
    required this.origin,
    required this.packageName,
    required this.sessionKey,
    required this.playing,
    required this.eventAtMs,
    this.title,
    this.artist,
    this.album,
    this.albumArtist,
    this.durationMs,
    this.positionMs,
  });

  final PlayerEventOrigin origin;

  /// Android package of the player app, e.g. `com.spotify.music`.
  final String packageName;

  /// Stable key for one media session instance (package + session token id),
  /// so two players — or two sessions of one player — never share state.
  final String sessionKey;

  final String? title;
  final String? artist;
  final String? album;
  final String? albumArtist;
  final int? durationMs;
  final int? positionMs;
  final bool playing;

  /// Wall-clock capture time (epoch ms) on the native side.
  final int eventAtMs;

  /// Decodes the map sent over the platform channel by
  /// `MediaListenerService`. Tolerant of missing keys and platform number
  /// widening.
  factory PlayerEvent.fromMap(Map<Object?, Object?> map) {
    String? str(String key) {
      final v = map[key];
      if (v is! String) return null;
      final trimmed = v.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    int? integer(String key) {
      final v = map[key];
      if (v is int) return v;
      if (v is num) return v.toInt();
      return null;
    }

    final origin = switch (map['origin']) {
      'session_ended' => PlayerEventOrigin.sessionEnded,
      'notification' => PlayerEventOrigin.notification,
      _ => PlayerEventOrigin.mediaSession,
    };

    return PlayerEvent(
      origin: origin,
      packageName: str('package') ?? 'unknown',
      sessionKey: str('sessionKey') ?? str('package') ?? 'unknown',
      title: str('title'),
      artist: str('artist'),
      album: str('album'),
      albumArtist: str('albumArtist'),
      durationMs: integer('durationMs'),
      positionMs: integer('positionMs'),
      playing: map['playing'] == true,
      eventAtMs: integer('eventAtMs') ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  @override
  String toString() =>
      'PlayerEvent($packageName ${playing ? 'playing' : 'paused'} '
      '$artist — $title)';
}
