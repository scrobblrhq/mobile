/// Canonical track produced by a [SourceParser] from a raw [PlayerEvent].
library;

class ParsedTrack {
  const ParsedTrack({
    required this.artist,
    required this.title,
    required this.sourceSlug,
    this.album,
    this.albumArtist,
    this.durationMs,
    this.confident = true,
  });

  final String artist;
  final String title;
  final String? album;
  final String? albumArtist;
  final int? durationMs;

  /// Source string submitted to the backend (`scrobbles.source`), e.g.
  /// `spotify`, `youtube-music`, `android`.
  final String sourceSlug;

  /// False when the parser had to guess (e.g. splitting a YouTube video
  /// title). Still scrobbled — server-side enrichment can fix metadata via
  /// MusicBrainz — but surfaced in the UI pipeline monitor.
  final bool confident;

  /// Identity used for dedupe/debounce. Case-insensitive artist+title;
  /// album excluded on purpose (the same song from a single vs. an album
  /// should not double-scrobble on metadata refinements).
  String get key => '${artist.toLowerCase()}${title.toLowerCase()}';

  ParsedTrack copyWith({int? durationMs, String? album}) => ParsedTrack(
    artist: artist,
    title: title,
    sourceSlug: sourceSlug,
    album: album ?? this.album,
    albumArtist: albumArtist,
    durationMs: durationMs ?? this.durationMs,
    confident: confident,
  );

  @override
  String toString() =>
      '$artist — $title${album != null ? ' ($album)' : ''} [$sourceSlug]';
}
