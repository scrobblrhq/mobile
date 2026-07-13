import 'package:flutter_test/flutter_test.dart';
import 'package:newfm_mobile/scrobbling/player_event.dart';
import 'package:newfm_mobile/scrobbling/scrobble_engine.dart';
import 'package:newfm_mobile/scrobbling/scrobble_rules.dart';

const settle = 5000;

PlayerEvent play(
  String artist,
  String title, {
  int? durationMs,
  int? positionMs,
  bool playing = true,
  String package = 'com.spotify.music',
}) {
  return PlayerEvent(
    origin: PlayerEventOrigin.mediaSession,
    packageName: package,
    sessionKey: '$package:1',
    title: title,
    artist: artist,
    durationMs: durationMs,
    positionMs: positionMs,
    playing: playing,
    eventAtMs: 0,
  );
}

PlayerEvent sessionEnded({String package = 'com.spotify.music'}) {
  return PlayerEvent(
    origin: PlayerEventOrigin.sessionEnded,
    packageName: package,
    sessionKey: '$package:1',
    playing: false,
    eventAtMs: 0,
  );
}

void main() {
  group('debounce (settle window)', () {
    test('a track is only accepted after it survives the settle window', () {
      final engine = ScrobbleEngine();

      var actions = engine.handleEvent(play('A', 'Song A'), 0);
      expect(actions, isEmpty);
      expect(engine.nextDeadlineMs(), settle);

      actions = engine.tick(settle);
      expect(actions, hasLength(1));
      expect(actions.single, isA<NowPlayingAction>());
      expect((actions.single as NowPlayingAction).track.title, 'Song A');
    });

    test('skipping through a playlist emits nothing', () {
      final engine = ScrobbleEngine();

      engine.handleEvent(play('A', 'Song A'), 0);
      engine.handleEvent(play('B', 'Song B'), 2000);
      var actions = engine.handleEvent(play('C', 'Song C'), 3500);
      expect(actions, isEmpty);

      // A and B never settled; C settles 5 s after ITS first sighting.
      actions = engine.tick(3500 + settle);
      expect(actions, hasLength(1));
      expect((actions.single as NowPlayingAction).track.title, 'Song C');
    });

    test('a paused candidate does not settle until it plays', () {
      final engine = ScrobbleEngine();

      engine.handleEvent(play('A', 'Song A', playing: false), 0);
      expect(engine.nextDeadlineMs(), isNull);
      expect(engine.tick(60000), isEmpty);

      // Starts playing at t=60s: settle restarts from there.
      engine.handleEvent(play('A', 'Song A'), 60000);
      final actions = engine.tick(60000 + settle);
      expect(actions.whereType<NowPlayingAction>(), hasLength(1));
    });
  });

  group('scrobble thresholds', () {
    test('scrobbles at 50% of a known duration, listened time counted from '
        'first sighting', () {
      final engine = ScrobbleEngine();
      // 200 s track → threshold 100 s.
      engine.handleEvent(play('A', 'Song A', durationMs: 200000), 0);
      engine.tick(settle);

      expect(engine.nextDeadlineMs(), 100000);
      final actions = engine.tick(100000);
      expect(actions, hasLength(1));
      final scrobble = actions.single as ScrobbleAction;
      expect(scrobble.track.title, 'Song A');
      expect(scrobble.playedAtMs, 0);
      expect(scrobble.listenedMs, 100000);

      // One scrobble per play session.
      expect(engine.nextDeadlineMs(), isNull);
      expect(engine.tick(400000), isEmpty);
    });

    test('unknown duration uses the 4-minute cap', () {
      final engine = ScrobbleEngine();
      engine.handleEvent(play('A', 'Song A'), 0);
      engine.tick(settle);
      expect(engine.nextDeadlineMs(), 240000);
    });

    test('long tracks cap at 4 minutes', () {
      final engine = ScrobbleEngine();
      // 20-minute mix.
      engine.handleEvent(play('A', 'Mix', durationMs: 1200000), 0);
      engine.tick(settle);
      expect(engine.nextDeadlineMs(), 240000);
    });

    test('tracks under 30 s never scrobble', () {
      final engine = ScrobbleEngine();
      engine.handleEvent(play('A', 'Skit', durationMs: 20000), 0);
      final actions = engine.tick(settle);
      expect(actions.whereType<NowPlayingAction>(), hasLength(1));
      expect(engine.nextDeadlineMs(), isNull);
      expect(engine.tick(600000), isEmpty);
    });
  });

  group('pause/resume accounting', () {
    test('paused time does not count toward the threshold', () {
      final engine = ScrobbleEngine();
      engine.handleEvent(play('A', 'Song A', durationMs: 200000), 0);
      engine.tick(settle);

      // Pause at t=50s with 50 s listened.
      engine.handleEvent(
        play('A', 'Song A', durationMs: 200000, playing: false),
        50000,
      );
      expect(engine.nextDeadlineMs(), isNull);
      expect(engine.tick(500000), isEmpty);

      // Resume at t=500s; 50 s remain to the 100 s threshold.
      engine.handleEvent(play('A', 'Song A', durationMs: 200000), 500000);
      expect(engine.nextDeadlineMs(), 550000);
      final actions = engine.tick(550000);
      expect(actions.single, isA<ScrobbleAction>());
      expect((actions.single as ScrobbleAction).listenedMs, 100000);
    });

    test('quick A→B→A flip keeps A\'s accumulated time', () {
      final engine = ScrobbleEngine();
      // 300 s track → threshold 150 s.
      engine.handleEvent(play('A', 'Song A', durationMs: 300000), 0);
      engine.tick(settle);

      // Peek at B for two seconds, then back to A.
      engine.handleEvent(play('B', 'Song B', durationMs: 300000), 60000);
      engine.handleEvent(play('A', 'Song A', durationMs: 300000), 62000);

      // B never settled → no now-playing for it; A's clock resumes with
      // 60 s banked, so the scrobble lands at 62 s + 90 s = 152 s.
      expect(engine.nextDeadlineMs(), 152000);
      final actions = engine.tick(152000);
      expect(actions.single, isA<ScrobbleAction>());
      expect((actions.single as ScrobbleAction).playedAtMs, 0);
    });
  });

  group('dedupe and replays', () {
    test('repeated metadata events for the same track emit nothing new', () {
      final engine = ScrobbleEngine();
      engine.handleEvent(play('A', 'Song A', durationMs: 200000), 0);
      engine.tick(settle);

      final actions = engine.handleEvent(
        play('A', 'Song A', durationMs: 200000, positionMs: 30000),
        30000,
      );
      expect(actions, isEmpty);
    });

    test('replay after a scrobble starts a fresh session', () {
      final engine = ScrobbleEngine();
      engine.handleEvent(play('A', 'Song A', durationMs: 200000), 0);
      engine.tick(settle);
      engine.tick(100000); // scrobbled

      // Repeat-one: position snaps back to ~0 while still playing.
      final actions = engine.handleEvent(
        play('A', 'Song A', durationMs: 200000, positionMs: 500),
        200000,
      );
      expect(actions.whereType<NowPlayingAction>(), hasLength(1));

      // Second scrobble after another 100 s of listening.
      expect(engine.nextDeadlineMs(), 300000);
      final second = engine.tick(300000);
      expect(second.single, isA<ScrobbleAction>());
      expect((second.single as ScrobbleAction).playedAtMs, 200000);
    });

    test('mid-track position reports do not restart the session', () {
      final engine = ScrobbleEngine();
      engine.handleEvent(play('A', 'Song A', durationMs: 200000), 0);
      engine.tick(settle);
      engine.tick(100000); // scrobbled

      final actions = engine.handleEvent(
        play('A', 'Song A', durationMs: 200000, positionMs: 150000),
        150000,
      );
      expect(actions, isEmpty);
    });
  });

  group('session lifecycle', () {
    test('a destroyed session before the threshold scrobbles nothing', () {
      final engine = ScrobbleEngine();
      engine.handleEvent(play('A', 'Song A', durationMs: 200000), 0);
      engine.tick(settle);

      engine.handleEvent(sessionEnded(), 50000);
      expect(engine.nextDeadlineMs(), isNull);
      expect(engine.tick(600000), isEmpty);
    });

    test('junk events (ads) freeze the clock but keep the play', () {
      final engine = ScrobbleEngine();
      engine.handleEvent(play('A', 'Song A', durationMs: 200000), 0);
      engine.tick(settle);

      // Spotify ad break at t=50s: parser rejects it → clock stops.
      engine.handleEvent(
        play('Spotify', 'Advertisement', durationMs: 30000),
        50000,
      );
      expect(engine.nextDeadlineMs(), isNull);
      expect(engine.tick(200000), isEmpty);

      // Same track resumes at t=200s: 50 s remain to threshold.
      engine.handleEvent(play('A', 'Song A', durationMs: 200000), 200000);
      final actions = engine.tick(250000);
      expect(actions.single, isA<ScrobbleAction>());
    });

    test('two players scrobble independently', () {
      final engine = ScrobbleEngine();
      engine.handleEvent(
        play('A', 'Song A', durationMs: 200000, package: 'com.spotify.music'),
        0,
      );
      engine.handleEvent(
        play('B', 'Song B', durationMs: 200000, package: 'org.videolan.vlc'),
        0,
      );

      final actions = engine.tick(settle);
      expect(actions.whereType<NowPlayingAction>(), hasLength(2));

      final scrobbles = engine.tick(100000);
      expect(scrobbles.whereType<ScrobbleAction>(), hasLength(2));
    });
  });

  group('rules', () {
    test('threshold math matches the server contract', () {
      const rules = ScrobbleRules();
      expect(rules.thresholdFor(null), 240000);
      expect(rules.thresholdFor(200000), 100000);
      expect(rules.thresholdFor(1200000), 240000);
      // Floor: never below the server's 30 s absolute rule.
      expect(rules.thresholdFor(40000), 30000);
      expect(rules.isEligible(20000), isFalse);
      expect(rules.isEligible(30000), isTrue);
      expect(rules.isEligible(null), isTrue);
    });
  });
}
