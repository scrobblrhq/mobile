/// Per-source metadata parsers.
///
/// The Android side reports structured `MediaMetadata` for every player, but
/// the *quality* of those fields differs per app: Spotify is clean, YouTube
/// Music appends " - Topic" to auto-generated artists, plain YouTube stuffs
/// "Artist - Title (Official Video)" into the title with the channel name as
/// artist, and ads/junk must be rejected before they hit the scrobble
/// pipeline. Each parser canonicalizes one source; the registry maps an
/// Android package name to its parser, with a generic fallback so unknown
/// players still scrobble.
library;

import 'parsed_track.dart';
import 'player_event.dart';

abstract class SourceParser {
  const SourceParser();

  /// Source identifier submitted with scrobbles from this parser.
  String get slug;

  /// Returns the canonical track, or `null` to reject the event
  /// (ads, missing metadata, non-music content).
  ParsedTrack? parse(PlayerEvent event);
}

/// Collapses whitespace, strips zero-width characters, trims.
String cleanText(String input) {
  return input
      .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

String? _clean(String? input) {
  if (input == null) return null;
  final cleaned = cleanText(input);
  return cleaned.isEmpty ? null : cleaned;
}

/// Fallback parser: trusts the media session fields as-is.
class GenericParser extends SourceParser {
  const GenericParser({this.slug = 'android'});

  @override
  final String slug;

  @override
  ParsedTrack? parse(PlayerEvent event) {
    final title = _clean(event.title);
    final artist = _clean(event.artist) ?? _clean(event.albumArtist);
    if (title == null || artist == null) return null;

    return ParsedTrack(
      artist: artist,
      title: title,
      album: _clean(event.album),
      albumArtist: _clean(event.albumArtist),
      durationMs: _validDuration(event.durationMs),
      sourceSlug: slug,
    );
  }
}

int? _validDuration(int? ms) => (ms == null || ms <= 0) ? null : ms;

/// Spotify: metadata is reliable, but ad breaks masquerade as tracks.
class SpotifyParser extends SourceParser {
  const SpotifyParser();

  static const _junk = {'advertisement', 'spotify', 'spotify ads'};

  @override
  String get slug => 'spotify';

  @override
  ParsedTrack? parse(PlayerEvent event) {
    final base = const GenericParser().parse(event);
    if (base == null) return null;
    if (_junk.contains(base.title.toLowerCase()) ||
        _junk.contains(base.artist.toLowerCase())) {
      return null;
    }
    return ParsedTrack(
      artist: base.artist,
      title: base.title,
      album: base.album,
      albumArtist: base.albumArtist,
      durationMs: base.durationMs,
      sourceSlug: slug,
    );
  }
}

/// Strips YouTube's " - Topic" suffix from auto-generated artist channels.
String stripTopicSuffix(String artist) {
  final cleaned = cleanText(artist.replaceFirst(RegExp(r'\s*-\s*Topic$'), ''));
  return cleaned.isEmpty ? artist : cleaned;
}

/// YouTube Music: near-clean metadata, aside from "- Topic" artists.
class YoutubeMusicParser extends SourceParser {
  const YoutubeMusicParser();

  @override
  String get slug => 'youtube-music';

  @override
  ParsedTrack? parse(PlayerEvent event) {
    final base = const GenericParser().parse(event);
    if (base == null) return null;
    return ParsedTrack(
      artist: stripTopicSuffix(base.artist),
      title: base.title,
      album: base.album,
      albumArtist: base.albumArtist,
      durationMs: base.durationMs,
      sourceSlug: slug,
    );
  }
}

/// Plain YouTube: the "artist" is a channel name and the "title" is a video
/// title. Heuristics: strip decorations like "(Official Video)", then split
/// "Artist - Title" on the first separator. When no split works we fall back
/// to channel-as-artist and flag the result as low-confidence.
class YoutubeParser extends SourceParser {
  const YoutubeParser();

  @override
  String get slug => 'youtube';

  /// Bracketed segments that are decoration, not part of the title.
  static final _decoration = RegExp(
    r'[(\[{【][^)\]}】]*'
    r'(official|video oficial|music video|lyric|lyrics|letra|audio|'
    r'visuali[sz]er|remaster(ed)?|hd|4k|m/?v|sub(t[ií]tulos)?|explicit)'
    r'[^)\]}】]*[)\]}】]',
    caseSensitive: false,
  );

  static final _separators = [' - ', ' – ', ' — ', ' | ', ' // '];

  static String _stripDecorations(String title) {
    final stripped = cleanText(title.replaceAll(_decoration, ' '));
    return stripped.isEmpty ? cleanText(title) : stripped;
  }

  static String _cleanChannel(String channel) {
    var name = cleanText(channel);
    name = name.replaceFirst(RegExp(r'\s*-\s*Topic$'), '');
    name = name.replaceFirst(RegExp(r'\s*VEVO$', caseSensitive: false), '');
    // Concatenated vevo channels: "TaylorSwiftVEVO" -> "TaylorSwift".
    name = name.replaceFirst(RegExp(r'VEVO$'), '');
    final cleaned = cleanText(name);
    return cleaned.isEmpty ? cleanText(channel) : cleaned;
  }

  @override
  ParsedTrack? parse(PlayerEvent event) {
    final rawTitle = _clean(event.title);
    if (rawTitle == null) return null;
    final channel = _clean(event.artist) ?? _clean(event.albumArtist);

    final title = _stripDecorations(rawTitle);

    for (final sep in _separators) {
      final idx = title.indexOf(sep);
      if (idx <= 0) continue;
      final artist = cleanText(title.substring(0, idx));
      final track = cleanText(title.substring(idx + sep.length));
      if (artist.isNotEmpty && track.isNotEmpty) {
        return ParsedTrack(
          artist: artist,
          title: track,
          durationMs: _validDuration(event.durationMs),
          sourceSlug: slug,
        );
      }
    }

    // No split: use the channel as artist if we have one.
    if (channel == null) return null;
    return ParsedTrack(
      artist: _cleanChannel(channel),
      title: title,
      durationMs: _validDuration(event.durationMs),
      sourceSlug: slug,
      confident: false,
    );
  }
}

/// A source the settings screen can toggle.
class KnownSource {
  const KnownSource(this.packageName, this.label, this.parser);

  final String packageName;
  final String label;
  final SourceParser parser;
}

const List<KnownSource> knownSources = [
  KnownSource('com.spotify.music', 'Spotify', SpotifyParser()),
  KnownSource(
    'com.google.android.apps.youtube.music',
    'YouTube Music',
    YoutubeMusicParser(),
  ),
  KnownSource('com.google.android.youtube', 'YouTube', YoutubeParser()),
  KnownSource(
    'app.revanced.android.apps.youtube.music',
    'YouTube Music (ReVanced)',
    YoutubeMusicParser(),
  ),
  KnownSource(
    'app.revanced.android.youtube',
    'YouTube (ReVanced)',
    YoutubeParser(),
  ),
  KnownSource('com.aspiro.tidal', 'Tidal', GenericParser(slug: 'tidal')),
  KnownSource('deezer.android.app', 'Deezer', GenericParser(slug: 'deezer')),
  KnownSource(
    'com.apple.android.music',
    'Apple Music',
    GenericParser(slug: 'apple-music'),
  ),
  KnownSource(
    'com.amazon.mp3',
    'Amazon Music',
    GenericParser(slug: 'amazon-music'),
  ),
  KnownSource('org.videolan.vlc', 'VLC', GenericParser(slug: 'vlc')),
  KnownSource(
    'com.maxmpz.audioplayer',
    'Poweramp',
    GenericParser(slug: 'poweramp'),
  ),
];

/// Maps a player package to its parser; unknown packages get the generic
/// fallback so any media app can scrobble.
class ParserRegistry {
  ParserRegistry({
    List<KnownSource> sources = knownSources,
    this.fallback = const GenericParser(),
  }) : _byPackage = {for (final s in sources) s.packageName: s.parser};

  final Map<String, SourceParser> _byPackage;
  final SourceParser fallback;

  SourceParser parserFor(String packageName) =>
      _byPackage[packageName] ?? fallback;
}
