import 'package:flutter_test/flutter_test.dart';
import 'package:newfm_mobile/scrobbling/player_event.dart';
import 'package:newfm_mobile/scrobbling/source_parsers.dart';

PlayerEvent event({
  String package = 'com.example.player',
  String? title,
  String? artist,
  String? album,
  String? albumArtist,
  int? durationMs,
  int? positionMs,
  bool playing = true,
}) {
  return PlayerEvent(
    origin: PlayerEventOrigin.mediaSession,
    packageName: package,
    sessionKey: '$package:1',
    title: title,
    artist: artist,
    album: album,
    albumArtist: albumArtist,
    durationMs: durationMs,
    positionMs: positionMs,
    playing: playing,
    eventAtMs: 0,
  );
}

void main() {
  group('GenericParser', () {
    const parser = GenericParser();

    test('passes clean metadata through', () {
      final track = parser.parse(
        event(
          title: 'Paranoid Android',
          artist: 'Radiohead',
          album: 'OK Computer',
          durationMs: 387000,
        ),
      );
      expect(track, isNotNull);
      expect(track!.artist, 'Radiohead');
      expect(track.title, 'Paranoid Android');
      expect(track.album, 'OK Computer');
      expect(track.durationMs, 387000);
      expect(track.sourceSlug, 'android');
      expect(track.confident, isTrue);
    });

    test('rejects events without a title or artist', () {
      expect(parser.parse(event(title: null, artist: 'X')), isNull);
      expect(parser.parse(event(title: 'X', artist: null)), isNull);
      expect(parser.parse(event(title: '  ', artist: 'X')), isNull);
    });

    test('falls back to albumArtist when artist is missing', () {
      final track = parser.parse(
        event(title: 'Song', artist: null, albumArtist: 'Boards of Canada'),
      );
      expect(track!.artist, 'Boards of Canada');
    });

    test('drops non-positive durations', () {
      expect(
        parser.parse(event(title: 'A', artist: 'B', durationMs: 0))!.durationMs,
        isNull,
      );
      expect(
        parser
            .parse(event(title: 'A', artist: 'B', durationMs: -1))!
            .durationMs,
        isNull,
      );
    });

    test('collapses whitespace and strips zero-width characters', () {
      final track = parser.parse(
        event(title: '  Song\u200b   Name ', artist: ' The\ufeff Band  '),
      );
      expect(track!.title, 'Song Name');
      expect(track.artist, 'The Band');
    });
  });

  group('SpotifyParser', () {
    const parser = SpotifyParser();

    test('rejects ad breaks', () {
      expect(
        parser.parse(event(title: 'Advertisement', artist: 'Spotify')),
        isNull,
      );
      expect(parser.parse(event(title: 'Song', artist: 'Spotify')), isNull);
    });

    test('accepts normal tracks with the spotify slug', () {
      final track = parser.parse(event(title: 'Nude', artist: 'Radiohead'));
      expect(track!.sourceSlug, 'spotify');
    });
  });

  group('YoutubeMusicParser', () {
    const parser = YoutubeMusicParser();

    test('strips " - Topic" from auto-generated channels', () {
      final track = parser.parse(
        event(title: 'Angel Echoes', artist: 'Four Tet - Topic'),
      );
      expect(track!.artist, 'Four Tet');
      expect(track.sourceSlug, 'youtube-music');
    });
  });

  group('YoutubeParser', () {
    const parser = YoutubeParser();

    test('splits "Artist - Title" video titles and strips decorations', () {
      final track = parser.parse(
        event(
          title: 'Mitski - Working for the Knife (Official Video)',
          artist: 'Mitski',
        ),
      );
      expect(track, isNotNull);
      expect(track!.artist, 'Mitski');
      expect(track.title, 'Working for the Knife');
      expect(track.confident, isTrue);
    });

    test('handles en dashes and bracketed decorations', () {
      final track = parser.parse(
        event(
          title: 'Boards of Canada – Roygbiv [Official Audio]',
          artist: 'WarpRecords',
        ),
      );
      expect(track!.artist, 'Boards of Canada');
      expect(track.title, 'Roygbiv');
    });

    test('keeps featuring credits that are not decorations', () {
      final track = parser.parse(
        event(title: 'Artist - Song (feat. Someone)', artist: 'Channel'),
      );
      expect(track!.title, 'Song (feat. Someone)');
    });

    test('falls back to cleaned channel name, flagged low-confidence', () {
      final track = parser.parse(
        event(title: 'Some Song Title', artist: 'TaylorSwiftVEVO'),
      );
      expect(track!.artist, 'TaylorSwift');
      expect(track.title, 'Some Song Title');
      expect(track.confident, isFalse);
    });

    test('rejects title-less events', () {
      expect(parser.parse(event(title: null, artist: 'Channel')), isNull);
    });
  });

  group('ParserRegistry', () {
    final registry = ParserRegistry();

    test('maps known packages to their parser', () {
      expect(registry.parserFor('com.spotify.music'), isA<SpotifyParser>());
      expect(
        registry.parserFor('com.google.android.apps.youtube.music'),
        isA<YoutubeMusicParser>(),
      );
      expect(
        registry.parserFor('com.google.android.youtube'),
        isA<YoutubeParser>(),
      );
    });

    test('falls back to the generic parser for unknown players', () {
      final parser = registry.parserFor('org.some.random.player');
      expect(parser, isA<GenericParser>());
      expect(parser.slug, 'android');
    });

    test('named generic parsers keep their slug', () {
      expect(registry.parserFor('com.aspiro.tidal').slug, 'tidal');
      expect(registry.parserFor('deezer.android.app').slug, 'deezer');
    });
  });
}
